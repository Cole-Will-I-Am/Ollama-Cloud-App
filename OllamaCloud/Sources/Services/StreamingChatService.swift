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
    private(set) var lastSentParentMessageID: UUID?

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
        let doneReason: String?
    }

    /// Shape of an Ollama/OpenAI mid-stream error line, e.g. {"error": "..."}.
    private struct StreamErrorPayload: Decodable {
        struct Detail: Decodable {
            let message: String?
        }

        let error: ErrorValue?

        enum ErrorValue: Decodable {
            case text(String)
            case detail(Detail)

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) {
                    self = .text(text)
                } else {
                    self = .detail(try container.decode(Detail.self))
                }
            }

            var message: String? {
                switch self {
                case .text(let text): return text.isEmpty ? nil : text
                case .detail(let detail): return detail.message?.isEmpty == false ? detail.message : nil
                }
            }
        }
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
        parentMessageID: UUID? = nil,
        tools: [ChatTool]? = nil,
        mcpManager: AnyObject? = nil,
        project: Project? = nil,
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

        var currentLeafID: UUID? = parentMessageID

        let didPrepareBranchingState = conversation.prepareBranchingState()
        if didPrepareBranchingState {
            conversation.updatedAt = Date()
            do {
                try modelContext.save()
            } catch {
                notice = "Branch state updated but could not be persisted."
            }
        }
        if currentLeafID == nil {
            currentLeafID = conversation.activeLeafID
        }
        lastSentParentMessageID = currentLeafID

        let selectedModel = conversation.modelName
        let provider = conversation.apiProvider
        let model = provider == .ollama ? SeerAssistantProfile.runtimeModelName(for: selectedModel) : selectedModel
        let shouldPreflightAvailability = provider == .ollama && !SeerAssistantProfile.isSeerModel(selectedModel)
        let thinkingEnabled = provider == .ollama && SeerAssistantProfile.shouldEnableThinking(
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

        let persistDecision = shouldPersistUserMessage(
            requested: persistUserMessage,
            conversation: conversation,
            resolvedRequestContent: resolvedRequestContent,
            imageBase64s: imageBase64s,
            parentMessageID: currentLeafID
        )
        if let existingUser = persistDecision.existingSiblingUser, !persistDecision.persist {
            // Retrying an already-persisted user message: anchor the request
            // (and the upcoming assistant reply) to it, not to its parent —
            // otherwise the request omits the user's message and the reply
            // becomes its sibling, dropping it from the active branch.
            currentLeafID = existingUser.id
        }
        if persistDecision.persist {
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
                parentID: currentLeafID,
                conversation: conversation
            )
            modelContext.insert(userMessage)
            currentLeafID = userMessage.id
            conversation.activeLeafID = userMessage.id
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
        // Scaffolds only apply to the Ollama provider; still resolve for other
        // providers so dangling references get cleaned, but don't mark the
        // scaffold as used when its prompt is dropped.
        let scaffoldResolution = prepareScaffoldSystemPrompt(
            conversation: conversation,
            modelContext: modelContext,
            markUsed: provider == .ollama
        )
        if scaffoldResolution.stateChanged {
            do {
                try modelContext.save()
            } catch {
                notice = "Scaffold state changed but could not be persisted."
            }
        }
        let branchMessages = currentLeafID != nil
            ? conversation.branchMessages(leafID: currentLeafID!)
            : conversation.messages.sorted { $0.createdAt < $1.createdAt }
        let systemPrompt: String = {
            let base: String
            if provider == .openai {
                base = conversation.systemPrompt
            } else {
                base = SeerAssistantProfile.mergedSystemPrompt(
                    baseSystemPrompt: conversation.systemPrompt,
                    selectedModelName: selectedModel
                )
            }
            // When tools are attached, keep the model aware they exist but not
            // fixated on them: use them naturally and silently when they help
            // (e.g. compute math/data instead of guessing), never recite or
            // advertise them, and don't introduce itself by its capabilities.
            guard let tools, !tools.isEmpty else { return base }
            let guidance = "You have utility tools available (such as calculating, running code, rendering visuals, or reading a web page). Use them naturally and silently whenever they genuinely improve the answer — for example, compute non-trivial math or data with a tool rather than guessing, and render a visual only when the user actually wants one. Never list, describe, or advertise your tools, don't narrate that you're 'using a tool', and don't introduce yourself by your capabilities — just do it and answer the user directly. For a greeting, reply with one short, friendly sentence."
            return base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? guidance
                : "\(base)\n\n\(guidance)"
        }()
        let requestMessages = Self.buildOutboundMessages(
            conversationMessages: branchMessages,
            systemPrompt: systemPrompt,
            scaffoldSystemPrompt: provider == .ollama ? scaffoldResolution.systemPrompt : nil
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
        let options: ChatOptions = {
            if provider == .openai { return baseOptions }
            return SeerAssistantProfile.tunedOptions(
                base: baseOptions,
                selectedModelName: selectedModel
            )
        }()

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
                        provider: provider,
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
                        // Reset buffers so a partial (e.g. thinking-only) first
                        // attempt isn't appended to by the retry's stream flush.
                        streamingContent = ""
                        streamingThinking = ""
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

            // Tool call loop (cross-platform: built-in tools everywhere, MCP on macOS)
            if let result = streamResult, !result.toolCalls.isEmpty {
                let hasBuiltinHandler = result.toolCalls.contains {
                    VisualsToolkit.handles($0.function.name)
                    || AssistantToolkit.handles($0.function.name)
                    || CodeToolkit.handles($0.function.name)
                }
                #if os(macOS)
                let hasMCPHandler = mcpManager is MCPClientManager
                #else
                let hasMCPHandler = false
                #endif

                if hasBuiltinHandler || hasMCPHandler {
                    var rounds = 0
                    let maxRounds = 10
                    var latestResult = result

                    toolRoundLoop: while !latestResult.toolCalls.isEmpty && rounds < maxRounds && !Task.isCancelled && conversation.modelContext != nil {
                        rounds += 1

                        // Persist tool_call message
                        let toolCallData = latestResult.toolCalls.map { call -> [String: Any] in
                            let argsAny = call.function.arguments.mapValues(\.anyValue)
                            if let id = call.id, !id.isEmpty {
                                return ["id": id, "name": call.function.name, "arguments": argsAny]
                            }
                            return ["name": call.function.name, "arguments": argsAny]
                        }
                        let toolCallJSON = (try? JSONSerialization.data(withJSONObject: toolCallData))
                            .flatMap { String(data: $0, encoding: .utf8) }

                        let toolCallMessage = Message(
                            role: "tool_call",
                            content: latestResult.content,
                            toolCallsJSON: toolCallJSON,
                            parentID: currentLeafID,
                            conversation: conversation
                        )
                        modelContext.insert(toolCallMessage)
                        currentLeafID = toolCallMessage.id

                        // Execute each tool call
                        for call in latestResult.toolCalls {
                            let toolName = call.function.name

                            self.isExecutingTool = true
                            self.toolCallStatus = "Calling \(toolName)..."

                            let resultText: String
                            let isError: Bool

                            if VisualsToolkit.handles(toolName) {
                                (resultText, isError) = VisualsToolkit.execute(
                                    toolName: toolName,
                                    arguments: call.function.arguments
                                )
                            } else if AssistantToolkit.handles(toolName) {
                                (resultText, isError) = await AssistantToolkit.execute(
                                    toolName: toolName,
                                    arguments: call.function.arguments,
                                    webAccessEnabled: UserDefaults.standard.bool(forKey: "web_access_enabled")
                                )
                            } else if CodeToolkit.handles(toolName), let project {
                                (resultText, isError) = CodeToolkit.execute(
                                    toolName: toolName,
                                    arguments: call.function.arguments,
                                    project: project,
                                    modelContext: modelContext
                                )
                            } else {
                                #if os(macOS)
                                if let manager = mcpManager as? MCPClientManager,
                                   let serverName = manager.serverForTool(named: toolName) {
                                    (resultText, isError) = await manager.callTool(
                                        serverName: serverName,
                                        toolName: toolName,
                                        arguments: call.function.arguments
                                    )
                                } else {
                                    (resultText, isError) = ("Unknown tool: \(toolName)", true)
                                }
                                #else
                                (resultText, isError) = ("Unknown tool: \(toolName)", true)
                                #endif
                            }
                            _ = isError // Error state is conveyed through the result text to the model

                            let toolResultMessage = Message(
                                role: "tool",
                                content: resultText,
                                toolName: toolName,
                                toolCallID: call.id,
                                parentID: currentLeafID,
                                conversation: conversation
                            )
                            modelContext.insert(toolResultMessage)
                            currentLeafID = toolResultMessage.id
                        }

                        conversation.activeLeafID = currentLeafID
                        self.isExecutingTool = false
                        self.toolCallStatus = nil

                        do {
                            try modelContext.save()
                        } catch {
                            self.error = "Failed to save tool output"
                            break toolRoundLoop
                        }

                        // Rebuild outbound messages and re-stream
                        let toolBranchMessages = currentLeafID != nil
                            ? conversation.branchMessages(leafID: currentLeafID!)
                            : conversation.messages.sorted { $0.createdAt < $1.createdAt }
                        currentMessages = Self.buildOutboundMessages(
                            conversationMessages: toolBranchMessages,
                            systemPrompt: SeerAssistantProfile.mergedSystemPrompt(
                                baseSystemPrompt: conversation.systemPrompt,
                                selectedModelName: conversation.modelName
                            ),
                            // Keep the scaffold across tool rounds so the
                            // model's role/tone doesn't shift mid-answer.
                            scaffoldSystemPrompt: provider == .ollama ? scaffoldResolution.systemPrompt : nil
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
                            parentID: currentLeafID,
                            conversation: conversation
                        )
                        modelContext.insert(errorMsg)
                        currentLeafID = errorMsg.id
                        conversation.activeLeafID = currentLeafID
                        try? modelContext.save()
                    }
                }
            }

            if let streamResult {
                finalEvalCount = streamResult.finalEvalCount
                streamingContent = streamResult.content
                streamingThinking = streamResult.thinking
                tokenCount = streamResult.tokenCount
                tokensPerSecond = streamResult.tokensPerSecond
                receivedAnyTokens = streamResult.sawTokens
                if streamResult.doneReason == "length", !streamResult.content.isEmpty {
                    notice = "The response hit the output token limit and may be cut off. Raise Max Tokens in parameters for longer answers."
                }
            }

            // A model may return only tool calls we can't execute here (e.g. an
            // MCP/unknown tool on iOS, where no handler runs). Surface a readable
            // message instead of persisting nothing and showing "No response".
            if let streamResult, !streamResult.toolCalls.isEmpty,
               streamingContent.isEmpty, streamingThinking.isEmpty, streamFailure == nil {
                let names = streamResult.toolCalls.map(\.function.name).joined(separator: ", ")
                streamingContent = "The model tried to use a tool that isn't available here (\(names)). Try rephrasing your request."
            }

            if let streamFailure {
                receivedAnyTokens = streamFailure.sawTokens
                if !Task.isCancelled {
                    handleStreamError(streamFailure.underlying)
                }
            }

            let wasCancelled = Task.isCancelled

            // Persist the assistant message if we got content — but never write
            // into a conversation that was deleted mid-stream. A deleted+saved
            // SwiftData model has a nil modelContext; resurrecting it corrupts
            // the store / crashes.
            if conversation.modelContext == nil {
                // Conversation deleted while streaming; drop the partial response.
            } else if !streamingContent.isEmpty || !streamingThinking.isEmpty {
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
                    parentID: currentLeafID,
                    conversation: conversation
                )
                modelContext.insert(assistantMessage)
                conversation.activeLeafID = assistantMessage.id
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
        imageBase64s: [String],
        parentMessageID: UUID?
    ) -> (persist: Bool, existingSiblingUser: Message?) {
        guard !requested else { return (true, nil) }

        let matchingSiblingUser = conversation.messages
            .filter { $0.role == "user" && $0.parentID == parentMessageID }
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last
        if let matchingSiblingUser {
            let siblingOutbound: String = {
                if let attachmentRequestContent = matchingSiblingUser.attachmentRequestContent,
                   !attachmentRequestContent.isEmpty {
                    return attachmentRequestContent
                }
                return matchingSiblingUser.content
            }()
            let siblingImages = Self.decodedImages(for: matchingSiblingUser) ?? []
            if siblingOutbound == resolvedRequestContent && siblingImages == imageBase64s {
                return (false, matchingSiblingUser)
            }
        }

        let comparisonUser = nearestAncestorUserMessage(
            in: conversation,
            from: parentMessageID
        ) ?? conversation.messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last(where: { $0.role == "user" })

        guard let latestUser = comparisonUser else {
            return (true, nil)
        }

        let latestOutbound: String = {
            if let attachmentRequestContent = latestUser.attachmentRequestContent,
               !attachmentRequestContent.isEmpty {
                return attachmentRequestContent
            }
            return latestUser.content
        }()

        let latestImages = Self.decodedImages(for: latestUser) ?? []
        return (latestOutbound != resolvedRequestContent || latestImages != imageBase64s, nil)
    }

    private func nearestAncestorUserMessage(in conversation: Conversation, from messageID: UUID?) -> Message? {
        guard let messageID else { return nil }

        let lookup = conversation.messages.reduce(into: [UUID: Message]()) { partialResult, message in
            partialResult[message.id] = message
        }
        var currentID: UUID? = messageID
        var visited: Set<UUID> = []

        while let id = currentID,
              visited.insert(id).inserted,
              let message = lookup[id] {
            if message.role == "user" {
                return message
            }
            currentID = message.parentID
        }
        return nil
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
                    tool_name: msg.toolName,
                    tool_call_id: msg.toolCallID
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
        modelContext: ModelContext,
        markUsed: Bool = true
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

        if markUsed {
            scaffold.lastUsedAt = Date()
            stateChanged = true
            AppTelemetry.track("scaffold_used_on_send", metadata: ["id": scaffold.id.uuidString])
        }
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
        provider: APIProvider = .ollama,
        idleTimeoutNanoseconds: UInt64,
        uiFlushIntervalNanoseconds: UInt64,
        onFlush: @Sendable (StreamFlushUpdate) async -> Void
    ) async throws -> StreamRunResult {
        switch provider {
        case .ollama:
            return try await performOllamaStream(
                model: model, messages: messages, options: options, think: think, tools: tools,
                idleTimeoutNanoseconds: idleTimeoutNanoseconds,
                uiFlushIntervalNanoseconds: uiFlushIntervalNanoseconds,
                onFlush: onFlush
            )
        case .openai:
            return try await performOpenAIStream(
                model: model, messages: messages, options: options, tools: tools,
                idleTimeoutNanoseconds: idleTimeoutNanoseconds,
                uiFlushIntervalNanoseconds: uiFlushIntervalNanoseconds,
                onFlush: onFlush
            )
        }
    }

    // MARK: - Ollama Stream

    nonisolated private static func performOllamaStream(
        model: String,
        messages: [ChatRequestMessage],
        options: ChatOptions,
        think: Bool,
        tools: [ChatTool]?,
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
        var doneReason: String?

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

                guard let data = line.data(using: .utf8) else { continue }
                // The server reports mid-stream failures as {"error": "..."} —
                // surface them instead of stalling until the idle timeout.
                if let errorPayload = try? JSONDecoder().decode(StreamErrorPayload.self, from: data),
                   let message = errorPayload.error?.message {
                    throw OllamaAPIError.serverError(message)
                }
                guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
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
                    doneReason = chunk.done_reason
                    break
                }
            }

            await flushPending(force: true)
            return makeStreamResult(
                fullContent: fullContent, fullThinking: fullThinking,
                tokenCount: tokenCount, tokensPerSecond: tokensPerSecond,
                finalEvalCount: finalEvalCount, sawTokens: sawTokens,
                streamStartedAt: streamStartedAt, firstTokenMs: firstTokenMs,
                flushCount: flushCount, flushIntervalTotalMs: flushIntervalTotalMs,
                toolCalls: accumulatedToolCalls,
                doneReason: doneReason
            )
        } catch {
            await flushPending(force: true)
            throw makeStreamFailure(
                error: error, sawTokens: sawTokens, streamStartedAt: streamStartedAt,
                firstTokenMs: firstTokenMs, flushCount: flushCount, flushIntervalTotalMs: flushIntervalTotalMs
            )
        }
    }

    // MARK: - OpenAI Stream (SSE)

    nonisolated private static func performOpenAIStream(
        model: String,
        messages: [ChatRequestMessage],
        options: ChatOptions,
        tools: [ChatTool]?,
        idleTimeoutNanoseconds: UInt64,
        uiFlushIntervalNanoseconds: UInt64,
        onFlush: @Sendable (StreamFlushUpdate) async -> Void
    ) async throws -> StreamRunResult {
        let streamStartedAt = Date()
        let (bytes, _) = try await OpenAIAPIClient.shared.streamChat(
            model: model,
            messages: messages,
            temperature: options.temperature,
            topP: options.top_p,
            maxTokens: options.num_predict,
            presencePenalty: options.presence_penalty,
            frequencyPenalty: options.frequency_penalty,
            seed: options.seed,
            tools: tools
        )

        let lineIterator = AsyncLineIterator(bytes.lines.makeAsyncIterator())

        var fullContent = ""
        var pendingContent = ""

        var tokenCount = 0
        var tokensPerSecond = 0.0
        var contentStartTime: Date?
        var firstTokenMs: Int?
        var sawTokens = false
        var finalEvalCount: Int?
        var doneReason: String?

        // Accumulate tool call deltas by index
        var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]

        var lastFlushTime: Date?
        var flushCount = 0
        var flushIntervalTotalMs = 0.0

        func flushPending(force: Bool = false) async {
            guard !pendingContent.isEmpty else { return }

            let now = Date()
            if !force, let lastFlushTime {
                let elapsedNanos = now.timeIntervalSince(lastFlushTime) * 1_000_000_000
                if elapsedNanos < Double(uiFlushIntervalNanoseconds) {
                    return
                }
            }

            let update = StreamFlushUpdate(
                contentDelta: pendingContent,
                thinkingDelta: "",
                tokenCount: tokenCount,
                tokensPerSecond: tokensPerSecond,
                isThinking: false
            )

            pendingContent.removeAll(keepingCapacity: true)

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

                // SSE format: lines starting with "data: "
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))

                if payload == "[DONE]" { break }

                guard let data = payload.data(using: .utf8) else { continue }
                // Error events ({"error": {...}}) would decode as an empty
                // chunk (all fields optional) and be silently skipped — check
                // for them explicitly and surface the message.
                if let errorPayload = try? JSONDecoder().decode(StreamErrorPayload.self, from: data),
                   let message = errorPayload.error?.message {
                    throw OllamaAPIError.serverError(message)
                }
                guard let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
                    continue
                }

                if let completionTokens = chunk.usage?.completion_tokens, completionTokens > 0 {
                    finalEvalCount = completionTokens
                }

                guard let choice = chunk.choices?.first else { continue }

                // Accumulate tool call deltas
                if let toolCallDeltas = choice.delta?.tool_calls {
                    for delta in toolCallDeltas {
                        var acc = toolCallAccumulators[delta.index] ?? (id: "", name: "", arguments: "")
                        if let id = delta.id { acc.id = id }
                        if let name = delta.function?.name, !name.isEmpty {
                            acc.name = mergeToolDeltaText(current: acc.name, incoming: name)
                        }
                        if let args = delta.function?.arguments, !args.isEmpty {
                            acc.arguments = mergeToolDeltaText(current: acc.arguments, incoming: args)
                        }
                        toolCallAccumulators[delta.index] = acc
                    }
                }

                if let token = choice.delta?.content, !token.isEmpty {
                    sawTokens = true
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

                if let finishReason = choice.finish_reason {
                    doneReason = finishReason
                    break
                }
            }

            await flushPending(force: true)

            // Convert accumulated tool calls to ChunkToolCall format
            let accumulatedToolCalls: [ChunkToolCall] = toolCallAccumulators
                .sorted { $0.key < $1.key }
                .compactMap { _, acc -> ChunkToolCall? in
                    guard !acc.name.isEmpty else { return nil }
                    let arguments: [String: JSONValue]
                    if let data = acc.arguments.data(using: .utf8),
                       let parsed = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
                        arguments = parsed
                    } else {
                        arguments = [:]
                    }
                    return ChunkToolCall(
                        id: acc.id.isEmpty ? nil : acc.id,
                        function: ChunkToolCallFunction(name: acc.name, arguments: arguments)
                    )
                }

            return makeStreamResult(
                fullContent: fullContent, fullThinking: "",
                tokenCount: tokenCount, tokensPerSecond: tokensPerSecond,
                finalEvalCount: finalEvalCount, sawTokens: sawTokens,
                streamStartedAt: streamStartedAt, firstTokenMs: firstTokenMs,
                flushCount: flushCount, flushIntervalTotalMs: flushIntervalTotalMs,
                toolCalls: accumulatedToolCalls,
                doneReason: doneReason
            )
        } catch {
            await flushPending(force: true)
            throw makeStreamFailure(
                error: error, sawTokens: sawTokens, streamStartedAt: streamStartedAt,
                firstTokenMs: firstTokenMs, flushCount: flushCount, flushIntervalTotalMs: flushIntervalTotalMs
            )
        }
    }

    // MARK: - Stream Result Helpers

    nonisolated private static func makeStreamResult(
        fullContent: String, fullThinking: String,
        tokenCount: Int, tokensPerSecond: Double,
        finalEvalCount: Int?, sawTokens: Bool,
        streamStartedAt: Date, firstTokenMs: Int?,
        flushCount: Int, flushIntervalTotalMs: Double,
        toolCalls: [ChunkToolCall],
        doneReason: String? = nil
    ) -> StreamRunResult {
        let completionMs = Int(Date().timeIntervalSince(streamStartedAt) * 1000)
        let averageFlushMs: Double? = flushCount > 1
            ? flushIntervalTotalMs / Double(flushCount - 1) : nil
        let metrics = StreamMetricsSnapshot(
            completionMs: completionMs, firstTokenMs: firstTokenMs,
            flushCount: flushCount, averageFlushMs: averageFlushMs
        )
        return StreamRunResult(
            content: fullContent, thinking: fullThinking,
            tokenCount: tokenCount, tokensPerSecond: tokensPerSecond,
            finalEvalCount: finalEvalCount, sawTokens: sawTokens,
            metrics: metrics, toolCalls: toolCalls,
            doneReason: doneReason
        )
    }

    nonisolated private static func makeStreamFailure(
        error: Error, sawTokens: Bool,
        streamStartedAt: Date, firstTokenMs: Int?,
        flushCount: Int, flushIntervalTotalMs: Double
    ) -> StreamRunFailure {
        let completionMs = Int(Date().timeIntervalSince(streamStartedAt) * 1000)
        let averageFlushMs: Double? = flushCount > 1
            ? flushIntervalTotalMs / Double(flushCount - 1) : nil
        let metrics = StreamMetricsSnapshot(
            completionMs: completionMs, firstTokenMs: firstTokenMs,
            flushCount: flushCount, averageFlushMs: averageFlushMs
        )
        return StreamRunFailure(underlying: error, sawTokens: sawTokens, metrics: metrics)
    }

    nonisolated private static func mergeToolDeltaText(current: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return current }
        guard !current.isEmpty else { return incoming }
        if incoming == current { return current }
        if incoming.hasPrefix(current) { return incoming }
        if current.hasPrefix(incoming) { return current }
        return current + incoming
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

    func retryLast(tools: [ChatTool]? = nil, mcpManager: AnyObject? = nil, project: Project? = nil, conversation: Conversation, modelContext: ModelContext) async {
        guard let lastSentRequestContent else { return }

        await sendMessage(
            content: lastSentContent ?? "",
            requestContent: lastSentRequestContent,
            imageBase64s: lastSentImageBase64s,
            attachmentSummary: lastSentAttachmentSummary,
            persistUserMessage: false,
            parentMessageID: lastSentParentMessageID,
            tools: tools,
            mcpManager: mcpManager,
            project: project,
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
