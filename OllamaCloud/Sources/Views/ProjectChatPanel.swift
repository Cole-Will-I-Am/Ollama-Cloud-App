import SwiftUI
import SwiftData

/// Collapsible chat panel embedded at the bottom of CodeWorkspaceView.
/// Uses the project's hidden Conversation for message persistence and
/// passes `project:` to StreamingChatService so CodeToolkit tools are included.
struct ProjectChatPanel: View {
    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
    @EnvironmentObject private var mcpManager: MCPClientManager
    #endif
    @Bindable var conversation: Conversation
    let project: Project
    @Binding var isCollapsed: Bool
    @ObservedObject var codeOutput: CodeBlockOutputState

    @StateObject private var streaming = StreamingChatService()
    @StateObject private var builder = CodebaseBuilder()
    @State private var input = ""
    @State private var lastFenceCount = 0
    @State private var buildMode = false
    @State private var showBuildConfig = false
    @FocusState private var isInputFocused: Bool

    private var isBusy: Bool { streaming.isStreaming || builder.isRunning }

    private var sortedMessages: [Message] {
        conversation.activeBranchMessages
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toggle bar
            toggleBar

            if !isCollapsed {
                Divider().background(Color.surface)
                chatContent

                if let error = streaming.error {
                    errorBanner(error)
                }

                if builder.isRunning, !builder.reviewerText.isEmpty {
                    reviewerBanner
                }

                buildControls
                inputBar
            }
        }
        .background(Color.bgSecondary)
        .sheet(isPresented: $showBuildConfig) {
            CodebaseBuildConfigView(project: project)
            #if os(macOS)
            .presentationBackground(Color.bgPrimary)
            #endif
        }
    }

    private var buildControls: some View {
        HStack(spacing: 10) {
            Button {
                buildMode.toggle()
                Haptic.selection()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: buildMode ? "hammer.fill" : "hammer")
                        .font(.system(size: 11))
                    Text("BUILD")
                        .font(.appLabel(9))
                        .luxuryTracking()
                }
                .foregroundStyle(buildMode ? Color.accent : Color.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(buildMode ? Color.accentSoft : Color.surface))
                .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .macPointingCursor()
            #endif

            if buildMode {
                Button { showBuildConfig = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .ultraLight))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .macPointingCursor()
                #endif
            }

            Spacer()

            if let status = builder.statusText {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.app(10))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var reviewerBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REVIEWER")
                .font(.appLabel(9))
                .luxuryTracking()
                .foregroundStyle(Color.accent)
            Text(builder.reviewerText)
                .font(.app(12, weight: .light))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentSoft.opacity(0.4))
    }

    private var toggleBar: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.textTertiary)
                    .frame(width: 32, height: 4)

                Spacer()

                if streaming.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedMessages, id: \.id) { message in
                        chatBubble(message)
                    }

                    if streaming.isThinking, !streaming.streamingThinking.isEmpty {
                        thinkingBubble
                    }

                    if streaming.isStreaming && !streaming.streamingContent.isEmpty {
                        streamingBubble
                    }

                    if streaming.isExecutingTool {
                        ToolExecutionIndicator(status: streaming.toolCallStatus)
                    }

                    Color.clear.frame(height: 1).id("chatBottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: sortedMessages.count) {
                withAnimation {
                    proxy.scrollTo("chatBottom", anchor: .bottom)
                }
            }
            .onChange(of: streaming.streamingContent) {
                proxy.scrollTo("chatBottom", anchor: .bottom)
                // Only re-extract when fence count changes (cheap perf optimization)
                let fences = streaming.streamingContent.components(separatedBy: "```").count - 1
                if fences != lastFenceCount {
                    lastFenceCount = fences
                    let result = CodeBlockExtractor.extract(
                        from: streaming.streamingContent,
                        messageID: UUID()
                    )
                    codeOutput.streamingBlocks = result.codeBlocks
                }
            }
            .onChange(of: streaming.isStreaming) { oldVal, newVal in
                if oldVal && !newVal {
                    // Stream completed — clear streaming blocks, rebuild from persisted
                    codeOutput.streamingBlocks = []
                    lastFenceCount = 0
                    codeOutput.rebuildFromMessages(sortedMessages)
                }
            }
            .onAppear {
                codeOutput.rebuildFromMessages(sortedMessages)
            }
            .onChange(of: sortedMessages.count) {
                if !streaming.isStreaming {
                    codeOutput.rebuildFromMessages(sortedMessages)
                }
            }
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: Message) -> some View {
        if message.role == "user" {
            HStack {
                Spacer()
                Text(message.content)
                    .font(.app(13))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentSoft, in: RoundedRectangle(cornerRadius: 12))
            }
        } else if message.role == "assistant" {
            let prose = CodeBlockExtractor.stripCodeBlocks(from: message.content)
            Text(prose)
                .font(.app(13))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
        } else if message.role == "tool" {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(message.toolName ?? "tool")
                        .font(.appLabel(10))
                        .foregroundStyle(Color.textTertiary)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.app(12, weight: .light))
                        .foregroundStyle(Color.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.bgTertiary, in: RoundedRectangle(cornerRadius: 10))
        }
        // Skip tool_call and system messages for a clean chat view
    }

    private var thinkingBubble: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("THINKING")
                .font(.appLabel(9))
                .luxuryTracking()
                .foregroundStyle(Color.textTertiary)
            Text(streaming.streamingThinking.suffix(60))
                .font(.app(11, weight: .light))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surface.opacity(0.5), in: Capsule())
    }

    private var streamingBubble: some View {
        let prose = CodeBlockExtractor.stripCodeBlocks(from: streaming.streamingContent)
        return Text(prose)
            .font(.app(13))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your project...", text: $input, axis: .vertical)
                .font(.app(13))
                .foregroundStyle(Color.textPrimary)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .onSubmit { sendMessage() }

            Button {
                if isBusy {
                    builder.cancel()
                    streaming.cancel(conversation: conversation, modelContext: modelContext)
                } else {
                    sendMessage()
                }
            } label: {
                Image(systemName: isBusy ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
                            ? Color.textTertiary
                            : Color.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.bgPrimary)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
            Text(message)
                .font(.app(12))
                .lineLimit(2)
            Spacer()
            if streaming.canRetryLast, !streaming.isStreaming {
                Button {
                    retryLast()
                } label: {
                    Text("RETRY")
                        .font(.appLabel(9))
                        .luxuryTracking()
                }
            }
        }
        .foregroundStyle(Color.danger)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.danger.opacity(0.06))
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) {
                streaming.error = nil
                streaming.recoveryAction = nil
            }
        }
    }

    private func retryLast() {
        streaming.error = nil
        streaming.recoveryAction = nil
        Task {
            var tools: [ChatTool] = VisualsToolkit.tools
            tools.append(contentsOf: CodeToolkit.tools)
            var manager: AnyObject? = nil
            #if os(macOS)
            if let mcpTools = mcpManager.ollamaTools() {
                tools.append(contentsOf: mcpTools)
            }
            manager = mcpManager
            #endif
            await streaming.retryLast(
                tools: tools.isEmpty ? nil : tools,
                mcpManager: manager,
                project: project,
                conversation: conversation,
                modelContext: modelContext
            )
        }
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parentForNewMessage = conversation.activeLeafID

        input = ""
        Haptic.impact()

        // Auto-name project from first user message
        if project.name == "New Project", conversation.messages.isEmpty {
            let preview = String(text.prefix(40))
            project.name = text.count > 40 ? "\(preview)..." : preview
            try? modelContext.save()
        }

        var manager: AnyObject? = nil
        #if os(macOS)
        manager = mcpManager
        #endif

        // Build mode: run the Builder + Reviewer loop instead of a single turn.
        if buildMode {
            Task {
                await builder.run(
                    userText: text,
                    project: project,
                    conversation: conversation,
                    reviewerModel: project.reviewerModelName ?? "",
                    reviewerEnabled: project.reviewerEnabled ?? true,
                    rounds: project.buildRounds ?? 2,
                    streaming: streaming,
                    mcpManager: manager,
                    modelContext: modelContext
                )
            }
            return
        }

        Task {
            var tools: [ChatTool] = VisualsToolkit.tools
            tools.append(contentsOf: CodeToolkit.tools)
            #if os(macOS)
            if let mcpTools = mcpManager.ollamaTools() {
                tools.append(contentsOf: mcpTools)
            }
            #endif
            await streaming.sendMessage(
                content: text,
                parentMessageID: parentForNewMessage,
                tools: tools.isEmpty ? nil : tools,
                mcpManager: manager,
                project: project,
                conversation: conversation,
                modelContext: modelContext
            )
        }
    }
}
