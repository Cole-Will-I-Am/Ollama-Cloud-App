import Foundation
import SwiftData

@MainActor
class StreamingChatService: ObservableObject {
    @Published var streamingContent = ""
    @Published var streamingThinking = ""
    @Published var isStreaming = false
    @Published var isThinking = false
    @Published var error: String?

    /// The last message content that was sent, for retry support
    private(set) var lastSentContent: String?

    private var streamTask: Task<Void, Never>?
    private var receivedAnyTokens = false
    private static let idleTimeout: UInt64 = 60_000_000_000 // 60s in nanoseconds

    func sendMessage(
        content: String,
        conversation: Conversation,
        modelContext: ModelContext
    ) {
        lastSentContent = content

        // Create and persist user message
        let userMessage = Message(role: "user", content: content, conversation: conversation)
        modelContext.insert(userMessage)
        conversation.updatedAt = Date()

        // Auto-title from first user message
        if conversation.messages.count <= 1 && conversation.title == "New Chat" {
            let preview = String(content.prefix(40))
            conversation.title = content.count > 40 ? "\(preview)..." : preview
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
            requestMessages.append(ChatRequestMessage(role: msg.role, content: msg.content))
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
                let assistantMessage = Message(
                    role: "assistant",
                    content: streamingContent,
                    thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
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

        // Idle timeout watchdog: cancel if no chunk for 60s
        let idleDeadline = IdleDeadline(timeout: Self.idleTimeout)

        for try await line in bytes.lines {
            guard !Task.isCancelled else { break }

            // Reset idle timer on every chunk
            idleDeadline.reset()

            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
                continue
            }

            if let thinking = chunk.message?.thinking, !thinking.isEmpty {
                isThinking = true
                streamingThinking += thinking
            }

            if let token = chunk.message?.content, !token.isEmpty {
                receivedAnyTokens = true
                if isThinking { isThinking = false }
                streamingContent += token
            }

            if chunk.done {
                break
            }

            // Check if idle deadline has been exceeded
            if idleDeadline.isExpired {
                throw OllamaAPIError.timeout
            }
        }

        idleDeadline.cancel()
    }

    private func handleStreamError(_ error: Error) {
        guard !Task.isCancelled else { return }

        if let apiError = error as? OllamaAPIError {
            self.error = apiError.userMessage
        } else {
            self.error = error.localizedDescription
        }
    }

    func cancel(conversation: Conversation, modelContext: ModelContext) {
        streamTask?.cancel()

        // Save partial content if any
        if !streamingContent.isEmpty || !streamingThinking.isEmpty {
            let partialMessage = Message(
                role: "assistant",
                content: streamingContent.isEmpty ? "[stopped during thinking]" : streamingContent + "\n\n[stopped]",
                thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
                conversation: conversation
            )
            modelContext.insert(partialMessage)
            try? modelContext.save()
        }

        streamingContent = ""
        streamingThinking = ""
        isStreaming = false
        isThinking = false
        streamTask = nil
    }
}

// MARK: - Idle Deadline

/// Tracks time since last activity to detect stalled streams.
private final class IdleDeadline: @unchecked Sendable {
    private let timeout: UInt64
    private var lastActivity: UInt64
    private var cancelled = false

    init(timeout: UInt64) {
        self.timeout = timeout
        self.lastActivity = DispatchTime.now().uptimeNanoseconds
    }

    func reset() {
        lastActivity = DispatchTime.now().uptimeNanoseconds
    }

    var isExpired: Bool {
        guard !cancelled else { return false }
        return (DispatchTime.now().uptimeNanoseconds - lastActivity) > timeout
    }

    func cancel() {
        cancelled = true
    }
}
