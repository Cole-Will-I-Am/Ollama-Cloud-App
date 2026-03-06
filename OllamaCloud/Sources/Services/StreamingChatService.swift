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

    // Tool execution state
    @Published var isExecutingTool = false
    @Published var toolCallStatus: String?

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
    private var finalEvalCount: Int?
    private static let idleTimeout: UInt64 = 60_000_000_000 // 60s in nanoseconds
    private static let uiFlushIntervalNanoseconds: UInt64 = 40_000_000 // 40ms

    private struct StreamFlushUpdate: Sendable {
        let contentDelta: String
        let thinkingDelta: String
        let tokenCount: Int
        let tokensPerSecond: Double
        let isThinking: Bool
    }

    private struct StreamMetricsSnapshot: Sendable {
        let completionMs: Int
        let firstTokenMs: Int?
        let flushCount: Int
        let averageFlushMs: Double?
    }

    private struct StreamRunResult: Sendable {
        let content: String
        let thinking: String
        let tokenCount: Int
        let tokensPerSecond: Double
        let finalEvalCount: Int?
        let sawTokens: Bool
        let metrics: StreamMetricsSnapshot
        let toolCalls: [ChunkToolCall]
    }

    private struct StreamRunFailure: Error {
        let underlying: Error
        let sawTokens: Bool
        let metrics: StreamMetricsSnapshot
    }

    func sendMessage(
        content: String,
        requestContent: String? = nil,
        imageBase64s: [String] = [],
        attachmentSummary: String? = nil,
        persistUserMessage: Bool = true,
        tools: [ChatTool]? = nil,
        mcpManager: AnyObject? = nil,
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
        let thinkingEnabled = SeerAssistantProfile.shouldEnableThinking(
            for: selectedModel,
            mode: conversation.thinkingMode
        )

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
        isExecutingTool = false
        toolCallStatus = nil
        streamingContent = ""
        streamingThinking = ""
        receivedAnyTokens = false
        tokenCount = 0
        tokensPerSecond = 0
        finalEvalCount = nil

        streamTask = Task {
            var streamResult: StreamRunResult?
            var streamFailure: StreamRunFailure?

            func executeStreamAttempt(messages: [ChatRequestMessage], currentTools: [ChatTool]?) async -> Result<StreamRunResult, StreamRunFailure> {
                do {
                    let result = try await Self.performStreamOffMain(
                        model: model,
                        messages: messages,
                        options: options,
                        think: thinkingEnabled,
                        tools: currentTools,
                        idleTimeoutNanoseconds: Self.idleTimeout,
                        uiFlushIntervalNanoseconds: Self.uiFlushIntervalNanoseconds
                    ) { [weak self] update in
                        guard let self else { return }
                        await self.applyStreamFlush(update)
                    }
                    return .success(result)
                } catch let failure as StreamRunFailure {
                    return .failure(failure)
                } catch {
                    let fallbackMetrics = StreamMetricsSnapshot(
                        completionMs: 0,
                        firstTokenMs: nil,
                        flushCount: 0,
                        averageFlushMs: nil
                    )
                    return .failure(
                        StreamRunFailure(
                            underlying: error,
                            sawTokens: false,
                            metrics: fallbackMetrics
                        )
                    )
                }
            }

            var currentMessages = requestMessages
            let currentTools = tools

            switch await executeStreamAttempt(messages: currentMessages, currentTools: currentTools) {
            case .success(let result):
                streamResult = result
            case .failure(let failure):
                let apiError = failure.underlying as? OllamaAPIError

                // Retry once on transient failure if we haven't received any tokens yet
                if !failure.sawTokens, apiError?.isTransient == true, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if !Task.isCancelled {
                        switch await executeStreamAttempt(messages: currentMessages, currentTools: currentTools) {
                        case .success(let result):
                            streamResult = result
                        case .failure(let retryFailure):
                            streamFailure = retryFailure
                        }
                    } else {
                        streamFailure = failure
                    }
                } else {
                    streamFailure = failure
                }
            }

            // Tool call loop (macOS only)
            #if os(macOS)
            if let result = streamResult, !result.toolCalls.isEmpty, let manager = mcpManager as? MCPClientManager {
                var rounds = 0
                let maxRounds = 10
                var latestResult = result

                toolRoundLoop: while !latestResult.toolCalls.isEmpty && rounds < maxRounds && !Task.isCancelled {
                    rounds += 1

                    // Persist tool_call message
                    let toolCallData = latestResult.toolCalls.map { call -> [String: Any] in
                        let argsAny = call.function.arguments.mapValues(\.anyValue)
                        return ["name": call.function.name, "arguments": argsAny]
                    }
                    let toolCallJSON = (try? JSONSerialization.data(withJSONObject: toolCallData))
                        .flatMap { String(data: $0, encoding: .utf8) }

                    let toolCallMessage = Message(
                        role: "tool_call",
                        content: latestResult.content,
                        toolCallsJSON: toolCallJSON,
                        conversation: conversation
                    )
                    modelContext.insert(toolCallMessage)

                    // Execute each tool call
                    for call in latestResult.toolCalls {
                        let toolName = call.function.name

                        self.isExecutingTool = true
                        self.toolCallStatus = "Calling \(toolName)..."

                        let serverName = manager.serverForTool(named: toolName)
                        let (resultText, isError): (String, Bool)
                        if let serverName {
                            (resultText, isError) = await manager.callTool(
                                serverName: serverName,
                                toolName: toolName,
                                arguments: call.function.arguments
                            )
                        } else {
                            (resultText, isError) = ("Unknown tool: \(toolName)", true)
                        }
                        _ = isError // Error state is conveyed through the result text to the model

                        let toolResultMessage = Message(
                            role: "tool",
                            content: resultText,
                            toolName: toolName,
                            conversation: conversation
                        )
                        modelContext.insert(toolResultMessage)
                    }

                    self.isExecutingTool = false
                    self.toolCallStatus = nil

                    do {
                        try modelContext.save()
                    } catch {
                        self.error = "Failed to save tool output"
                        break toolRoundLoop
                    }

                    // Rebuild outbound messages and re-stream
                    currentMessages = Self.buildOutboundMessages(
                        conversationMessages: conversation.messages,
                        systemPrompt: SeerAssistantProfile.mergedSystemPrompt(
                            baseSystemPrompt: conversation.systemPrompt,
                            selectedModelName: conversation.modelName
                        ),
                        scaffoldSystemPrompt: nil
                    )

                    // Reset streaming state for next round
                    streamingContent = ""
                    streamingThinking = ""
                    tokenCount = 0
                    tokensPerSecond = 0

                    switch await executeStreamAttempt(messages: currentMessages, currentTools: currentTools) {
                    case .success(let nextResult):
                        latestResult = nextResult
                        streamResult = nextResult
                    case .failure(let failure):
                        streamFailure = failure
                        break toolRoundLoop
                    }
                }

                if rounds >= maxRounds && !latestResult.toolCalls.isEmpty {
                    let errorMsg = Message(
                        role: "tool",
                        content: "Maximum tool call rounds (\(maxRounds)) reached. Stopping.",
                        toolName: "system",
                        conversation: conversation
                    )
                    modelContext.insert(errorMsg)
                    try? modelContext.save()
                }
            }
            #endif

            if let streamResult {
                finalEvalCount = streamResult.finalEvalCount
                streamingContent = streamResult.content
                streamingThinking = streamResult.thinking
                tokenCount = streamResult.tokenCount
                tokensPerSecond = streamResult.tokensPerSecond
                receivedAnyTokens = streamResult.sawTokens
            }
            if let streamFailure {
                receivedAnyTokens = streamFailure.sawTokens
                if !Task.isCancelled {
                    handleStreamError(streamFailure.underlying)
                }
            }

            let wasCancelled = Task.isCancelled

            // Persist the assistant message if we got content
            if !streamingContent.isEmpty || !streamingThinking.isEmpty {
                let persistedTokenCount = finalEvalCount ?? (tokenCount > 0 ? tokenCount : nil)
                let persistedContent: String
                if wasCancelled {
                    persistedContent = streamingContent.isEmpty
                        ? "[stopped during thinking]"
                        : streamingContent + "\n\n[stopped]"
                } else {
                    persistedContent = streamingContent
                }
                let assistantMessage = Message(
                    role: "assistant",
                    content: persistedContent,
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
            } else if self.error == nil, !wasCancelled {
                self.error = "No response received. Try again."
                self.recoveryAction = .retry
            }

            let streamOutcome: String = {
                if wasCancelled { return "cancelled" }
                if self.error != nil { return "error" }
                return "completed"
            }()
            trackStreamMetrics(
                outcome: streamOutcome,
                metrics: streamResult?.metrics ?? streamFailure?.metrics
            )

            streamingContent = ""
            streamingThinking = ""
            isStreaming = false
            isThinking = false
            isExecutingTool = false
            toolCallStatus = nil
            if self.error == nil {
                recoveryAction = nil
            }
            streamTask = nil
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
            // Skip tool_call messages — they're intermediate markers, not part of Ollama's protocol
            if msg.role == "tool_call" { continue }

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
                    images: decodedImages(for: msg),
                    tool_name: msg.toolName
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

    private func applyStreamFlush(_ update: StreamFlushUpdate) {
        if !update.thinkingDelta.isEmpty {
            streamingThinking += update.thinkingDelta
        }
        if !update.contentDelta.isEmpty {
            streamingContent += update.contentDelta
            receivedAnyTokens = true
        }
        tokenCount = update.tokenCount
        tokensPerSecond = update.tokensPerSecond
        isThinking = update.isThinking
    }

    nonisolated private static func performStreamOffMain(
        model: String,
        messages: [ChatRequestMessage],
        options: ChatOptions,
        think: Bool,
        tools: [ChatTool]? = nil,
        idleTimeoutNanoseconds: UInt64,
        uiFlushIntervalNanoseconds: UInt64,
        onFlush: @Sendable (StreamFlushUpdate) async -> Void
    ) async throws -> StreamRunResult {
        let streamStartedAt = Date()
        let (bytes, _) = try await OllamaAPIClient.shared.streamChat(
            model: model,
            messages: messages,
            think: think,
            options: options,
            tools: tools
        )

        let lineIterator = AsyncLineIterator(bytes.lines.makeAsyncIterator())

        var fullContent = ""
        var fullThinking = ""
        var pendingContent = ""
        var pendingThinking = ""

        var tokenCount = 0
        var tokensPerSecond = 0.0
        var contentStartTime: Date?
        var firstTokenMs: Int?
        var sawTokens = false
        var finalEvalCount: Int?
        var thinkingActive = false
        var accumulatedToolCalls: [ChunkToolCall] = []

        var lastFlushTime: Date?
        var flushCount = 0
        var flushIntervalTotalMs = 0.0

        func flushPending(force: Bool = false) async {
            let hasPendingText = !pendingContent.isEmpty || !pendingThinking.isEmpty
            guard hasPendingText else { return }

            let now = Date()
            if !force, let lastFlushTime {
                let elapsedNanos = now.timeIntervalSince(lastFlushTime) * 1_000_000_000
                if elapsedNanos < Double(uiFlushIntervalNanoseconds) {
                    return
                }
            }

            let update = StreamFlushUpdate(
                contentDelta: pendingContent,
                thinkingDelta: pendingThinking,
                tokenCount: tokenCount,
                tokensPerSecond: tokensPerSecond,
                isThinking: thinkingActive
            )

            pendingContent.removeAll(keepingCapacity: true)
            pendingThinking.removeAll(keepingCapacity: true)

            if let lastFlushTime {
                flushIntervalTotalMs += now.timeIntervalSince(lastFlushTime) * 1000
            }
            lastFlushTime = now
            flushCount += 1

            await onFlush(update)
        }

        do {
            while !Task.isCancelled {
                guard let line = try await Self.nextLineWithTimeout(
                    from: lineIterator,
                    timeoutNanoseconds: idleTimeoutNanoseconds
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
                    thinkingActive = true
                    pendingThinking += thinking
                    fullThinking += thinking
                    await flushPending()
                }

                if let toolCalls = chunk.message?.tool_calls, !toolCalls.isEmpty {
                    accumulatedToolCalls.append(contentsOf: toolCalls)
                }

                if let token = chunk.message?.content, !token.isEmpty {
                    sawTokens = true
                    thinkingActive = false
                    tokenCount += 1
                    pendingContent += token
                    fullContent += token

                    if contentStartTime == nil {
                        contentStartTime = Date()
                        firstTokenMs = Int(contentStartTime!.timeIntervalSince(streamStartedAt) * 1000)
                    }
                    if let contentStartTime {
                        let elapsed = Date().timeIntervalSince(contentStartTime)
                        if elapsed > 0.1 {
                            tokensPerSecond = Double(tokenCount) / elapsed
                        }
                    }
                    await flushPending()
                }

                if chunk.done {
                    break
                }
            }

            await flushPending(force: true)
            let completionMs = Int(Date().timeIntervalSince(streamStartedAt) * 1000)
            let averageFlushMs: Double? = {
                guard flushCount > 1 else { return nil }
                return flushIntervalTotalMs / Double(flushCount - 1)
            }()
            let metrics = StreamMetricsSnapshot(
                completionMs: completionMs,
                firstTokenMs: firstTokenMs,
                flushCount: flushCount,
                averageFlushMs: averageFlushMs
            )

            return StreamRunResult(
                content: fullContent,
                thinking: fullThinking,
                tokenCount: tokenCount,
                tokensPerSecond: tokensPerSecond,
                finalEvalCount: finalEvalCount,
                sawTokens: sawTokens,
                metrics: metrics,
                toolCalls: accumulatedToolCalls
            )
        } catch {
            await flushPending(force: true)
            let completionMs = Int(Date().timeIntervalSince(streamStartedAt) * 1000)
            let averageFlushMs: Double? = {
                guard flushCount > 1 else { return nil }
                return flushIntervalTotalMs / Double(flushCount - 1)
            }()
            let metrics = StreamMetricsSnapshot(
                completionMs: completionMs,
                firstTokenMs: firstTokenMs,
                flushCount: flushCount,
                averageFlushMs: averageFlushMs
            )
            throw StreamRunFailure(underlying: error, sawTokens: sawTokens, metrics: metrics)
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

    func retryLast(tools: [ChatTool]? = nil, mcpManager: AnyObject? = nil, conversation: Conversation, modelContext: ModelContext) async {
        guard let lastSentRequestContent else { return }

        await sendMessage(
            content: lastSentContent ?? "",
            requestContent: lastSentRequestContent,
            imageBase64s: lastSentImageBase64s,
            attachmentSummary: lastSentAttachmentSummary,
            persistUserMessage: false,
            tools: tools,
            mcpManager: mcpManager,
            conversation: conversation,
            modelContext: modelContext
        )
    }

    func cancel(conversation _: Conversation, modelContext _: ModelContext) {
        streamTask?.cancel()
        notice = nil
        recoveryAction = nil
    }

    private func trackStreamMetrics(outcome: String, metrics: StreamMetricsSnapshot?) {
        guard let metrics else { return }

        var metadata: [String: String] = [
            "outcome": outcome,
            "completion_ms": String(metrics.completionMs),
            "flush_count": String(metrics.flushCount)
        ]

        if let firstTokenMs = metrics.firstTokenMs {
            metadata["first_token_ms"] = String(firstTokenMs)
        }
        if let averageFlushMs = metrics.averageFlushMs {
            metadata["avg_flush_ms"] = String(format: "%.1f", averageFlushMs)
        }

        AppTelemetry.track("stream_metrics", metadata: metadata)
    }

#if DEBUG
    struct StreamBatchingEvent: Sendable {
        let offsetMs: Int
        let thinking: String?
        let content: String?

        init(offsetMs: Int, thinking: String? = nil, content: String? = nil) {
            self.offsetMs = offsetMs
            self.thinking = thinking
            self.content = content
        }
    }

    struct StreamBatchingFlush: Sendable, Equatable {
        let offsetMs: Int
        let contentDelta: String
        let thinkingDelta: String
        let tokenCount: Int
    }

    struct StreamBatchingSimulation: Sendable, Equatable {
        let flushes: [StreamBatchingFlush]
        let finalContent: String
        let finalThinking: String
        let tokenCount: Int
        let firstTokenMs: Int?
        let flushCount: Int
        let averageFlushMs: Double?
    }

    nonisolated static func simulateBatching(
        events: [StreamBatchingEvent],
        think: Bool,
        flushIntervalMs: Int = 40,
        forceFinalFlush: Bool = true
    ) -> StreamBatchingSimulation {
        let sorted = events.sorted { $0.offsetMs < $1.offsetMs }
        let streamStartedAt = Date(timeIntervalSince1970: 0)

        var fullContent = ""
        var fullThinking = ""
        var pendingContent = ""
        var pendingThinking = ""
        var tokenCount = 0
        var firstTokenMs: Int?
        var contentStartTime: Date?

        var flushes: [StreamBatchingFlush] = []
        var flushCount = 0
        var flushIntervalTotalMs = 0.0
        var lastFlushTime: Date?
        var thinkingActive = false

        func now(for offsetMs: Int) -> Date {
            streamStartedAt.addingTimeInterval(Double(offsetMs) / 1000)
        }

        func flush(now: Date, offsetMs: Int, force: Bool = false) {
            let hasPendingText = !pendingContent.isEmpty || !pendingThinking.isEmpty
            guard hasPendingText else { return }

            if !force, let lastFlushTime {
                let elapsedMs = now.timeIntervalSince(lastFlushTime) * 1000
                if elapsedMs < Double(flushIntervalMs) {
                    return
                }
            }

            if let lastFlushTime {
                flushIntervalTotalMs += now.timeIntervalSince(lastFlushTime) * 1000
            }
            lastFlushTime = now
            flushCount += 1

            flushes.append(
                StreamBatchingFlush(
                    offsetMs: offsetMs,
                    contentDelta: pendingContent,
                    thinkingDelta: pendingThinking,
                    tokenCount: tokenCount
                )
            )

            fullContent += pendingContent
            fullThinking += pendingThinking
            pendingContent.removeAll(keepingCapacity: true)
            pendingThinking.removeAll(keepingCapacity: true)
        }

        for event in sorted {
            let now = now(for: event.offsetMs)

            if think, let thinking = event.thinking, !thinking.isEmpty {
                thinkingActive = true
                pendingThinking += thinking
                flush(now: now, offsetMs: event.offsetMs)
            }

            if let content = event.content, !content.isEmpty {
                thinkingActive = false
                tokenCount += 1
                pendingContent += content
                if contentStartTime == nil {
                    contentStartTime = now
                    firstTokenMs = event.offsetMs
                }
                flush(now: now, offsetMs: event.offsetMs)
            }
        }

        if forceFinalFlush {
            let tailOffset = sorted.last?.offsetMs ?? 0
            flush(now: now(for: tailOffset), offsetMs: tailOffset, force: true)
        }

        let averageFlushMs: Double? = {
            guard flushCount > 1 else { return nil }
            return flushIntervalTotalMs / Double(flushCount - 1)
        }()

        _ = thinkingActive // keep parity with production state progression

        return StreamBatchingSimulation(
            flushes: flushes,
            finalContent: fullContent,
            finalThinking: fullThinking,
            tokenCount: tokenCount,
            firstTokenMs: firstTokenMs,
            flushCount: flushCount,
            averageFlushMs: averageFlushMs
        )
    }
#endif

    nonisolated private static func nextLineWithTimeout(
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
