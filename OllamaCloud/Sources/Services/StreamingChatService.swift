import Foundation
import SwiftData

@MainActor
class StreamingChatService: ObservableObject {
    @Published var streamingContent = ""
    @Published var streamingThinking = ""
    @Published var isStreaming = false
    @Published var isThinking = false
    @Published var error: String?

    // Streaming metrics
    @Published var tokenCount: Int = 0
    @Published var tokensPerSecond: Double = 0

    /// The last message content that was sent, for retry support
    private(set) var lastSentContent: String?
    private(set) var lastSentRequestContent: String?
    private(set) var lastSentImageBase64s: [String] = []
    private(set) var lastSentAttachmentSummary: String?

    private var streamTask: Task<Void, Never>?
    private var receivedAnyTokens = false
    private var contentStartTime: Date?
    private var finalEvalCount: Int?
    private static let idleTimeout: UInt64 = 60_000_000_000 // 60s in nanoseconds

    func sendMessage(
        content: String,
        requestContent: String? = nil,
        imageBase64s: [String] = [],
        attachmentSummary: String? = nil,
        conversation: Conversation,
        modelContext: ModelContext
    ) {
        let resolvedRequestContent = requestContent ?? content
        let resolvedDisplayContent: String = {
            if let attachmentSummary, !attachmentSummary.isEmpty {
                if content.isEmpty {
                    return attachmentSummary
                }
                return "\(content)\n\n\(attachmentSummary)"
            }
            return content
        }()

        lastSentContent = content
        lastSentRequestContent = resolvedRequestContent
        lastSentImageBase64s = imageBase64s
        lastSentAttachmentSummary = attachmentSummary

        let imageJSON: String? = {
            guard !imageBase64s.isEmpty,
                  let data = try? JSONEncoder().encode(imageBase64s),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }()

        // Create and persist user message
        let userMessage = Message(
            role: "user",
            content: resolvedDisplayContent,
            attachmentRequestContent: resolvedRequestContent == resolvedDisplayContent ? nil : resolvedRequestContent,
            imageBase64sJSON: imageJSON,
            conversation: conversation
        )
        modelContext.insert(userMessage)
        conversation.updatedAt = Date()

        // Auto-title from first user message
        if conversation.messages.count <= 1 && conversation.title == "New Chat" {
            let titleSource = content.isEmpty ? (attachmentSummary ?? "Attachment") : content
            let preview = String(titleSource.prefix(40))
            conversation.title = titleSource.count > 40 ? "\(preview)..." : preview
        }

        do {
            try modelContext.save()
        } catch {
            self.error = "Failed to save message"
            return
        }

        // Build messages array for API
        var requestMessages: [ChatRequestMessage] = []

        if !conversation.systemPrompt.isEmpty {
            requestMessages.append(ChatRequestMessage(role: "system", content: conversation.systemPrompt))
        }

        let sorted = (conversation.messages).sorted { $0.createdAt < $1.createdAt }
        for msg in sorted {
            let outboundContent: String
            if msg.role == "user",
               let attachmentRequestContent = msg.attachmentRequestContent,
               !attachmentRequestContent.isEmpty {
                outboundContent = attachmentRequestContent
            } else {
                outboundContent = msg.content
            }

            let outboundImages: [String]? = {
                guard msg.role == "user",
                      let json = msg.imageBase64sJSON,
                      let data = json.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode([String].self, from: data),
                      !decoded.isEmpty else {
                    return nil
                }
                return decoded
            }()

            requestMessages.append(
                ChatRequestMessage(role: msg.role, content: outboundContent, images: outboundImages)
            )
        }

        let options = ChatOptions(
            temperature: conversation.temperature,
            top_p: conversation.topP,
            top_k: conversation.topK,
            min_p: conversation.minP > 0 ? conversation.minP : nil,
            typical_p: conversation.typicalP < 1.0 ? conversation.typicalP : nil,
            repeat_penalty: conversation.repeatPenalty != 1.1 ? conversation.repeatPenalty : nil,
            repeat_last_n: conversation.repeatLastN != 64 ? conversation.repeatLastN : nil,
            presence_penalty: conversation.presencePenalty != 0 ? conversation.presencePenalty : nil,
            frequency_penalty: conversation.frequencyPenalty != 0 ? conversation.frequencyPenalty : nil,
            num_predict: conversation.numPredict,
            seed: conversation.seed != 0 ? conversation.seed : nil,
            num_batch: conversation.numBatch != 512 ? conversation.numBatch : nil,
            num_thread: conversation.numThread != 0 ? conversation.numThread : nil
        )

        let model = conversation.modelName

        // Start streaming
        isStreaming = true
        isThinking = false
        streamingContent = ""
        streamingThinking = ""
        error = nil
        receivedAnyTokens = false
        tokenCount = 0
        tokensPerSecond = 0
        contentStartTime = nil
        finalEvalCount = nil

        streamTask = Task {
            do {
                try await performStream(
                    model: model,
                    messages: requestMessages,
                    options: options
                )
            } catch {
                let apiError = error as? OllamaAPIError

                // Retry once on transient failure if we haven't received any tokens yet
                if !receivedAnyTokens, apiError?.isTransient == true, !Task.isCancelled {
                    // Wait 1s before retry
                    try? await Task.sleep(nanoseconds: 1_000_000_000)

                    if !Task.isCancelled {
                        do {
                            try await performStream(
                                model: model,
                                messages: requestMessages,
                                options: options
                            )
                        } catch {
                            handleStreamError(error)
                        }
                    }
                } else {
                    handleStreamError(error)
                }
            }

            // Persist the assistant message if we got content
            if !streamingContent.isEmpty || !streamingThinking.isEmpty {
                let persistedTokenCount = finalEvalCount ?? (tokenCount > 0 ? tokenCount : nil)
                let assistantMessage = Message(
                    role: "assistant",
                    content: streamingContent,
                    thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
                    outputTokenCount: persistedTokenCount,
                    conversation: conversation
                )
                modelContext.insert(assistantMessage)
                conversation.updatedAt = Date()
                do {
                    try modelContext.save()
                } catch {
                    self.error = "Failed to save response"
                }
            }

            streamingContent = ""
            streamingThinking = ""
            isStreaming = false
            isThinking = false
        }
    }

    /// Perform the actual stream reading with idle timeout
    private func performStream(
        model: String,
        messages: [ChatRequestMessage],
        options: ChatOptions
    ) async throws {
        let (bytes, _) = try await OllamaAPIClient.shared.streamChat(
            model: model,
            messages: messages,
            options: options
        )

        let lineIterator = AsyncLineIterator(bytes.lines.makeAsyncIterator())

        while !Task.isCancelled {
            guard let line = try await nextLineWithTimeout(
                from: lineIterator,
                timeoutNanoseconds: Self.idleTimeout
            ) else {
                break
            }
            guard !Task.isCancelled else { break }

            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
                continue
            }

            if let evalCount = chunk.eval_count, evalCount > 0 {
                finalEvalCount = evalCount
            }

            if let thinking = chunk.message?.thinking, !thinking.isEmpty {
                if !isThinking {
                    isThinking = true
                }
                streamingThinking += thinking
            }

            if let token = chunk.message?.content, !token.isEmpty {
                receivedAnyTokens = true
                if isThinking {
                    isThinking = false
                }
                tokenCount += 1
                if contentStartTime == nil { contentStartTime = Date() }
                let elapsed = Date().timeIntervalSince(contentStartTime!)
                if elapsed > 0.1 {
                    tokensPerSecond = Double(tokenCount) / elapsed
                }
                streamingContent += token
            }

            if chunk.done {
                break
            }
        }
    }

    private func handleStreamError(_ error: Error) {
        guard !Task.isCancelled else { return }

        if let apiError = error as? OllamaAPIError {
            self.error = apiError.userMessage
        } else {
            self.error = error.localizedDescription
        }
    }

    var canRetryLast: Bool {
        lastSentRequestContent != nil
    }

    func retryLast(conversation: Conversation, modelContext: ModelContext) {
        guard let lastSentRequestContent else { return }

        sendMessage(
            content: lastSentContent ?? "",
            requestContent: lastSentRequestContent,
            imageBase64s: lastSentImageBase64s,
            attachmentSummary: lastSentAttachmentSummary,
            conversation: conversation,
            modelContext: modelContext
        )
    }

    func cancel(conversation: Conversation, modelContext: ModelContext) {
        streamTask?.cancel()

        // Save partial content if any
        if !streamingContent.isEmpty || !streamingThinking.isEmpty {
            let partialMessage = Message(
                role: "assistant",
                content: streamingContent.isEmpty ? "[stopped during thinking]" : streamingContent + "\n\n[stopped]",
                thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
                outputTokenCount: tokenCount > 0 ? tokenCount : nil,
                conversation: conversation
            )
            modelContext.insert(partialMessage)
            do {
                try modelContext.save()
            } catch {
                self.error = "Failed to save partial response"
            }
        }

        streamingContent = ""
        streamingThinking = ""
        isStreaming = false
        isThinking = false
        streamTask = nil
    }

    private func nextLineWithTimeout(
        from iterator: AsyncLineIterator,
        timeoutNanoseconds: UInt64
    ) async throws -> String? {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await iterator.next()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw OllamaAPIError.timeout
            }

            let first = try await group.next()
            group.cancelAll()
            return first ?? nil
        }
    }
}

private actor AsyncLineIterator {
    private var iterator: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator

    init(_ iterator: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator) {
        self.iterator = iterator
    }

    func next() async throws -> String? {
        var copy = iterator
        let value = try await copy.next()
        iterator = copy
        return value
    }
}
