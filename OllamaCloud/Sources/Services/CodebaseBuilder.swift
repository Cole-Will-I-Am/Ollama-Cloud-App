import Foundation
import SwiftData

/// Orchestrates the Codebases "Builder + Reviewer" loop, mirroring the manticthink
/// website's cbRunBuild. The Builder turn reuses the existing `StreamingChatService`
/// tool loop (executing CodeToolkit file tools against the codebase's `Project`),
/// then a Reviewer model critiques the changes; the critique is fed back as the
/// Builder's next turn, for N rounds or until the Reviewer approves.
@MainActor
final class CodebaseBuilder: ObservableObject {
    enum Phase: Equatable { case idle, building, reviewing }

    @Published var isRunning = false
    @Published var phase: Phase = .idle
    @Published var statusText: String?
    /// Live-streamed reviewer critique for the current round (transient UI only).
    @Published var reviewerText: String = ""
    /// Model names driving the current run, for labeling the chat thread.
    @Published var builderModel: String = ""
    @Published var reviewerModel: String = ""
    @Published var error: String?

    private var cancelled = false

    func cancel() {
        cancelled = true
        isRunning = false
        statusText = nil
        phase = .idle
    }

    /// - Parameter streaming: the caller's chat service, reused so the Builder's
    ///   stream renders in the same panel the user is watching.
    func run(
        userText: String,
        project: Project,
        conversation: Conversation,
        reviewerModel: String,
        reviewerEnabled: Bool,
        rounds: Int,
        streaming: StreamingChatService,
        mcpManager: AnyObject?,
        modelContext: ModelContext
    ) async {
        guard !isRunning else { return }
        isRunning = true
        cancelled = false
        error = nil
        reviewerText = ""

        let totalRounds = max(1, min(6, rounds))
        let effectiveReviewer = reviewerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? conversation.modelName
            : reviewerModel
        builderModel = conversation.modelName
        self.reviewerModel = effectiveReviewer

        var builderInput = userText

        for round in 0..<totalRounds {
            if cancelled { break }
            phase = .building
            statusText = "Builder working… (round \(round + 1)/\(totalRounds))"

            // Refresh the Builder's system prompt with the current codebase context.
            conversation.systemPrompt = CodebasePrompts.builderPersona(project)
                + "\n\n" + CodebasePrompts.compileCodebaseContext(project)

            let before = fileSnapshot(project)

            var tools: [ChatTool] = CodeToolkit.tools
            #if os(macOS)
            if let mgr = mcpManager as? MCPClientManager, let mcpTools = mgr.ollamaTools() {
                tools.append(contentsOf: mcpTools)
            }
            #endif

            await streaming.sendMessage(
                content: builderInput,
                parentMessageID: conversation.activeLeafID,
                tools: tools,
                mcpManager: mcpManager,
                project: project,
                conversation: conversation,
                modelContext: modelContext
            )
            await waitForStreamingToFinish(streaming)

            if let err = streaming.error { error = err; break }
            if cancelled { break }

            guard reviewerEnabled else { break }

            let changed = changedPaths(before: before, project: project)
            let summary = lastAssistantContent(conversation)

            phase = .reviewing
            statusText = "Reviewer reviewing… (round \(round + 1)/\(totalRounds))"
            reviewerText = ""
            let critique = await streamReview(
                model: effectiveReviewer,
                system: CodebasePrompts.reviewerPersona(),
                user: CodebasePrompts.reviewerUserPrompt(project, builderSummary: summary, changedPaths: changed)
            )

            if cancelled { break }
            if critique.isEmpty || CodebasePrompts.reviewerApproves(critique) { break }

            // Feed the critique back to the Builder as its next turn (mirrors the
            // website's cbExpandConversation, where reviewer → a user message).
            builderInput = "Reviewer feedback on the previous changes:\n\(critique)"
        }

        phase = .idle
        statusText = nil
        reviewerText = ""
        isRunning = false
    }

    // MARK: - Helpers

    /// `sendMessage` starts a detached stream task and returns early; wait until
    /// it settles before running the Reviewer so we review the finished output.
    private func waitForStreamingToFinish(_ streaming: StreamingChatService) async {
        while streaming.isStreaming {
            try? await Task.sleep(nanoseconds: 120_000_000)
            if cancelled { break }
        }
    }

    private func fileSnapshot(_ project: Project) -> [String: Date] {
        var map: [String: Date] = [:]
        for file in project.files where !file.isDirectory { map[file.path] = file.updatedAt }
        return map
    }

    private func changedPaths(before: [String: Date], project: Project) -> [String] {
        var changed: [String] = []
        for file in project.files where !file.isDirectory {
            if let previous = before[file.path] {
                if file.updatedAt != previous { changed.append(file.path) }
            } else {
                changed.append(file.path) // newly created
            }
        }
        return changed.sorted()
    }

    private func lastAssistantContent(_ conversation: Conversation) -> String {
        conversation.activeBranchMessages.last { $0.role == "assistant" }?.content ?? ""
    }

    private func streamReview(model: String, system: String, user: String) async -> String {
        let messages = [
            ChatRequestMessage(role: "system", content: system),
            ChatRequestMessage(role: "user", content: user),
        ]
        do {
            let (bytes, response) = try await OllamaAPIClient.shared.streamChat(model: model, messages: messages, think: false)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 { return "" }
            var acc = ""
            for try await line in bytes.lines {
                if cancelled { break }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
                guard let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else { continue }
                if let content = chunk.message?.content, !content.isEmpty {
                    acc += content
                    reviewerText = acc
                }
                if chunk.done { break }
            }
            return acc
        } catch {
            return ""
        }
    }
}
