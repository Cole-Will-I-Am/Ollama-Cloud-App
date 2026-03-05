import Foundation
import SwiftData

@MainActor
class StreamingChatService: ObservableObject {
    enum RecoveryAction: Equatable {
        case retry
        case chooseModel
    }

    @Published var streamingContent = ""
    @Published var streamingThinking = ""
    @Published var isStreaming = false
    @Published var isThinking = false
    @Published var error: String?
    @Published var notice: String?
    @Published var recoveryAction: RecoveryAction?

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
    private static let uiFlushIntervalNanoseconds: UInt64 = 40_000_000 // 40ms

    private var bufferedContent = ""
    private var bufferedThinking = ""
    private var bufferedTokenCount = 0
    private var bufferedTokensPerSecond: Double = 0
    private var pendingFlushTask: Task<Void, Never>?

    private var streamStartTime: Date?
    private var firstTokenLatencyMs: Double?
    private var uiFlushCount = 0
    private var uiFlushIntervalTotalMs: Double = 0
    private var lastUIFlushTime: Date?

    func sendMessage(
        content: String,
        requestContent: String? = nil,
        imageBase64s: [String] = [],
        attachmentSummary: String? = nil,
        persistUserMessage: Bool = true,
        conversation: Conversation,
        modelContext: ModelContext
    ) async {
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
        recoveryAction = nil
        error = nil
        notice = nil

        let selectedModel = conversation.modelName
        let model = SeerAssistantProfile.runtimeModelName(for: selectedModel)
        let shouldPreflightAvailability = !SeerAssistantProfile.isSeerModel(selectedModel)
        let thinkingEnabled = SeerAssistantProfile.shouldEnableThinking(for: selectedModel)

        if shouldPreflightAvailability {
            do {
                let modelAvailable = try await OllamaAPIClient.shared.isModelAvailable(model)
                guard modelAvailable else {
                    error = OllamaAPIError.modelUnavailable.userMessage
                    recoveryAction = .chooseModel
                    return
                }
            } catch let apiError as OllamaAPIError {
                self.error = apiError.userMessage
                recoveryAction = apiError.suggestsModelReselect ? .chooseModel : .retry
                return
            } catch let caughtError {
                self.error = caughtError.localizedDescription
                recoveryAction = .retry
                return
            }
        }

        if shouldPersistUserMessage(
            requested: persistUserMessage,
            conversation: conversation,
            resolvedRequestContent: resolvedRequestContent,
            imageBase64s: imageBase64s
        ) {
            let imageJSON: String? = {
                guard !imageBase64s.isEmpty,
                      let data = try? JSONEncoder().encode(imageBase64s),
                      let json = String(data: data, encoding: .utf8) else {
                    return nil
                }
                return json
            }()

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
        }

        // Build messages array for API
        let scaffoldResolution = prepareScaffoldSystemPrompt(
            conversation: conversation,
            modelContext: modelContext
        )
        if scaffoldResolution.stateChanged {
            do {
                try modelContext.save()
            } catch {
                notice = "Scaffold state changed but could not be persisted."
            }
        }
        let requestMessages = Self.buildOutboundMessages(
            conversationMessages: conversation.messages,
            systemPrompt: SeerAssistantProfile.mergedSystemPrompt(
                baseSystemPrompt: conversation.systemPrompt,
                selectedModelName: selectedModel
            ),
            scaffoldSystemPrompt: scaffoldResolution.systemPrompt
        )

        let baseOptions = ChatOptions(
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
        let options = SeerAssistantProfile.tunedOptions(
            base: baseOptions,
            selectedModelName: selectedModel
        )

        // Start streaming
        isStreaming = true
        isThinking = false
        streamingContent = ""
        streamingThinking = ""
        receivedAnyTokens = false
        resetBufferedStreamState()
        streamStartTime = Date()
        tokenCount = 0
        tokensPerSecond = 0
        contentStartTime = nil
        finalEvalCount = nil

        streamTask = Task {
            do {
                try await performStream(
                    model: model,
                    messages: requestMessages,
                    options: options,
                    think: thinkingEnabled
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
                                options: options,
                                think: thinkingEnabled
                            )
                        } catch {
                            handleStreamError(error)
                        }
                    }
                } else {
                    handleStreamError(error)
                }
            }

            flushBufferedUpdates(force: true)

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
            } else if self.error == nil, !Task.isCancelled {
                self.error = "No response received. Try again."
                self.recoveryAction = .retry
            }

            let streamOutcome: String = {
                if Task.isCancelled { return "cancelled" }
                if self.error != nil { return "error" }
                return "completed"
            }()
            trackStreamMetrics(outcome: streamOutcome)

            streamingContent = ""
            streamingThinking = ""
            isStreaming = false
            isThinking = false
            if self.error == nil {
                recoveryAction = nil
            }
            resetBufferedStreamState()
        }
    }

    private func shouldPersistUserMessage(
        requested: Bool,
        conversation: Conversation,
        resolvedRequestContent: String,
        imageBase64s: [String]
    ) -> Bool {
        guard !requested else { return true }

        guard let latestUser = conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == "user" }) else {
            return true
        }

        let latestOutbound: String = {
            if let attachmentRequestContent = latestUser.attachmentRequestContent,
               !attachmentRequestContent.isEmpty {
                return attachmentRequestContent
            }
            return latestUser.content
        }()

        let latestImages = Self.decodedImages(for: latestUser) ?? []
        return latestOutbound != resolvedRequestContent || latestImages != imageBase64s
    }

    nonisolated static func buildOutboundMessages(
        conversationMessages: [Message],
        systemPrompt: String,
        scaffoldSystemPrompt: String?
    ) -> [ChatRequestMessage] {
        var requestMessages: [ChatRequestMessage] = []

        if let scaffoldSystemPrompt,
           !scaffoldSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestMessages.append(ChatRequestMessage(role: "system", content: scaffoldSystemPrompt))
        }

        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestMessages.append(ChatRequestMessage(role: "system", content: systemPrompt))
        }

        let sorted = conversationMessages.sorted { $0.createdAt < $1.createdAt }
        for msg in sorted {
            let outboundContent: String
            if msg.role == "user",
               let attachmentRequestContent = msg.attachmentRequestContent,
               !attachmentRequestContent.isEmpty {
                outboundContent = attachmentRequestContent
            } else {
                outboundContent = msg.content
            }

            requestMessages.append(
                ChatRequestMessage(
                    role: msg.role,
                    content: outboundContent,
                    images: decodedImages(for: msg)
                )
            )
        }

        return requestMessages
    }

    struct ScaffoldResolution {
        let systemPrompt: String?
        let stateChanged: Bool
    }

    func prepareScaffoldSystemPrompt(
        conversation: Conversation,
        modelContext: ModelContext
    ) -> ScaffoldResolution {
        guard AppConfig.reasoningScaffoldsEnabled else {
            return ScaffoldResolution(systemPrompt: nil, stateChanged: false)
        }

        guard let rawID = conversation.activeScaffoldID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty else {
            return ScaffoldResolution(systemPrompt: nil, stateChanged: false)
        }

        guard let scaffoldID = UUID(uuidString: rawID) else {
            let changed = clearActiveScaffold(
                conversation: conversation,
                reason: "invalid_id",
                message: "Active reasoning scaffold could not be loaded and was cleared."
            )
            return ScaffoldResolution(systemPrompt: nil, stateChanged: changed)
        }

        let descriptor = FetchDescriptor<ReasoningScaffold>(
            predicate: #Predicate<ReasoningScaffold> { scaffold in
                scaffold.id == scaffoldID
            }
        )

        guard let scaffold = try? modelContext.fetch(descriptor).first else {
            let changed = clearActiveScaffold(
                conversation: conversation,
                reason: "missing",
                message: "Active reasoning scaffold is missing and was cleared."
            )
            return ScaffoldResolution(systemPrompt: nil, stateChanged: changed)
        }

        let activeScope = AccountScope.currentKey()
        guard scaffold.accountScopeKey == activeScope else {
            let changed = clearActiveScaffold(
                conversation: conversation,
                reason: "scope_mismatch",
                message: "Active reasoning scaffold was from another account scope and was cleared."
            )
            return ScaffoldResolution(systemPrompt: nil, stateChanged: changed)
        }

        let compiled = ReasoningScaffoldCompiler.compile(scaffold)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compiled.isEmpty else {
            notice = "Reasoning scaffold was empty and skipped."
            return ScaffoldResolution(systemPrompt: nil, stateChanged: false)
        }

        var stateChanged = false
        if conversation.activeScaffoldName != scaffold.name {
            conversation.activeScaffoldName = scaffold.name
            stateChanged = true
        }

        scaffold.lastUsedAt = Date()
        stateChanged = true
        AppTelemetry.track("scaffold_used_on_send", metadata: ["id": scaffold.id.uuidString])
        return ScaffoldResolution(systemPrompt: compiled, stateChanged: stateChanged)
    }

    private func clearActiveScaffold(
        conversation: Conversation,
        reason: String,
        message: String
    ) -> Bool {
        let hasScaffold = (conversation.activeScaffoldID?.isEmpty == false)
            || (conversation.activeScaffoldName?.isEmpty == false)
        conversation.activeScaffoldID = nil
        conversation.activeScaffoldName = nil
        conversation.updatedAt = Date()
        notice = message
        AppTelemetry.track("scaffold_cleared", metadata: ["reason": reason])
        return hasScaffold
    }

    nonisolated private static func decodedImages(for message: Message) -> [String]? {
        guard message.role == "user",
              let json = message.imageBase64sJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              !decoded.isEmpty else {
            return nil
        }
        return decoded
    }

    /// Perform the actual stream reading with idle timeout
    private func performStream(
        model: String,
        messages: [ChatRequestMessage],
        options: ChatOptions,
        think: Bool
    ) async throws {
        let (bytes, _) = try await OllamaAPIClient.shared.streamChat(
            model: model,
            messages: messages,
            think: think,
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

            if think, let thinking = chunk.message?.thinking, !thinking.isEmpty {
                if !isThinking {
                    isThinking = true
                }
                bufferedThinking += thinking
                scheduleBufferedFlushIfNeeded()
            }

            if let token = chunk.message?.content, !token.isEmpty {
                receivedAnyTokens = true
                if isThinking {
                    isThinking = false
                }
                bufferedTokenCount += 1
                if contentStartTime == nil {
                    contentStartTime = Date()
                    if let streamStartTime {
                        firstTokenLatencyMs = Date().timeIntervalSince(streamStartTime) * 1000
                    }
                }
                let elapsed = Date().timeIntervalSince(contentStartTime!)
                if elapsed > 0.1 {
                    bufferedTokensPerSecond = Double(bufferedTokenCount) / elapsed
                }
                bufferedContent += token
                scheduleBufferedFlushIfNeeded()
            }

            if chunk.done {
                flushBufferedUpdates(force: true)
                break
            }
        }
    }

    private func handleStreamError(_ error: Error) {
        guard !Task.isCancelled else { return }

        if let apiError = error as? OllamaAPIError {
            self.error = apiError.userMessage
            self.recoveryAction = apiError.suggestsModelReselect ? .chooseModel : (canRetryLast ? .retry : nil)
        } else {
            self.error = error.localizedDescription
            self.recoveryAction = canRetryLast ? .retry : nil
        }
    }

    var canRetryLast: Bool {
        lastSentRequestContent != nil
    }

    func retryLast(conversation: Conversation, modelContext: ModelContext) async {
        guard let lastSentRequestContent else { return }

        await sendMessage(
            content: lastSentContent ?? "",
            requestContent: lastSentRequestContent,
            imageBase64s: lastSentImageBase64s,
            attachmentSummary: lastSentAttachmentSummary,
            persistUserMessage: false,
            conversation: conversation,
            modelContext: modelContext
        )
    }

    func cancel(conversation: Conversation, modelContext: ModelContext) {
        streamTask?.cancel()
        flushBufferedUpdates(force: true)

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
        notice = nil
        recoveryAction = nil
        streamTask = nil
    }

    private func resetBufferedStreamState() {
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        bufferedContent.removeAll(keepingCapacity: true)
        bufferedThinking.removeAll(keepingCapacity: true)
        bufferedTokenCount = 0
        bufferedTokensPerSecond = 0
        streamStartTime = nil
        firstTokenLatencyMs = nil
        uiFlushCount = 0
        uiFlushIntervalTotalMs = 0
        lastUIFlushTime = nil
    }

    private func scheduleBufferedFlushIfNeeded() {
        guard pendingFlushTask == nil else { return }

        pendingFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.uiFlushIntervalNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushBufferedUpdates()
        }
    }

    private func flushBufferedUpdates(force: Bool = false) {
        if force {
            pendingFlushTask?.cancel()
        }
        pendingFlushTask = nil

        let hasTextUpdates = !bufferedContent.isEmpty || !bufferedThinking.isEmpty
        let hasMetricsUpdates = tokenCount != bufferedTokenCount
            || abs(tokensPerSecond - bufferedTokensPerSecond) > 0.0001
        guard hasTextUpdates || hasMetricsUpdates else { return }

        if !bufferedThinking.isEmpty {
            streamingThinking += bufferedThinking
            bufferedThinking.removeAll(keepingCapacity: true)
        }

        if !bufferedContent.isEmpty {
            streamingContent += bufferedContent
            bufferedContent.removeAll(keepingCapacity: true)
        }

        if tokenCount != bufferedTokenCount {
            tokenCount = bufferedTokenCount
        }
        if abs(tokensPerSecond - bufferedTokensPerSecond) > 0.0001 {
            tokensPerSecond = bufferedTokensPerSecond
        }

        let now = Date()
        if let lastUIFlushTime {
            uiFlushIntervalTotalMs += now.timeIntervalSince(lastUIFlushTime) * 1000
        }
        lastUIFlushTime = now
        uiFlushCount += 1
    }

    private func trackStreamMetrics(outcome: String) {
        guard let streamStartTime else { return }

        var metadata: [String: String] = [
            "outcome": outcome,
            "completion_ms": String(Int(Date().timeIntervalSince(streamStartTime) * 1000)),
            "flush_count": String(uiFlushCount)
        ]

        if let firstTokenLatencyMs {
            metadata["first_token_ms"] = String(Int(firstTokenLatencyMs.rounded()))
        }
        if uiFlushCount > 1 {
            let avgInterval = uiFlushIntervalTotalMs / Double(uiFlushCount - 1)
            metadata["avg_flush_ms"] = String(format: "%.1f", avgInterval)
        }

        AppTelemetry.track("stream_metrics", metadata: metadata)
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
