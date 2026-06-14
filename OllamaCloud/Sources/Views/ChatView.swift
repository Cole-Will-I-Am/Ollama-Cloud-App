import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var network: NetworkMonitor
    #if os(macOS)
    @EnvironmentObject private var mcpManager: MCPClientManager
    #endif
    @Bindable var conversation: Conversation
    var project: Project?
    /// Lightweight context project (Projects tab). When set, its compiled
    /// instructions + context files are injected as a system message on every send.
    var chatProject: ChatProject?
    @StateObject private var streaming = StreamingChatService()
    @AppStorage("visualizations_enabled") private var visualizationsEnabled = true
    @AppStorage("web_access_enabled") private var webAccessEnabled = false
    @State private var input = ""
    @State private var showModelPicker = false
    @State private var showParameters = false
    @State private var showStreamingThinking = true
    @State private var isAtBottom = true
    @State private var hasNewMessage = false
    @State private var shouldAutoFollowStreaming = true
    @State private var sentFirstTokenHaptic = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var bottomAnchorMaxY: CGFloat = 0
    @State private var lastStreamingAutoScrollAt = Date.distantPast
    @FocusState private var isInputFocused: Bool
    @State private var showAttachmentOptions = false
    @State private var showScaffoldLibrary = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var showGitHubBrowser = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingImageAttachments: [PendingImageAttachment] = []
    @State private var pendingFileAttachments: [PendingFileAttachment] = []
    @State private var attachmentError: String?
    @State private var scaffoldPersistenceError: String?
    @State private var exportError: String?
    #if os(iOS)
    @State private var exportShareItem: ExportShareItem?
    @StateObject private var dictation = SpeechDictation()
    @State private var dictationBaseText = ""
    #endif
    @State private var showVisionModelWarning = false
    @State private var forkParentID: UUID?
    #if os(macOS)
    @State private var isFileDropTargeted = false
    @State private var isHoveringNewBadge = false
    #endif

    private struct PendingImageAttachment: Identifiable, Equatable {
        let id = UUID()
        let base64: String
        let byteCount: Int
    }

    private struct PendingFileAttachment: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let content: String
        let originalCharacterCount: Int
    }

    private var sortedMessages: [Message] {
        conversation.activeBranchMessages
    }
    /// Compiled lightweight-project context, recomputed on each send so edits to
    /// the project's instructions/files apply immediately (matches the website).
    private var projectContextPrompt: String? {
        guard let chatProject else { return nil }
        return ProjectContextCompiler.compile(chatProject)
    }
    private static let streamingAutoScrollThrottleInterval: TimeInterval = 0.1

    var body: some View {
        let messages = sortedMessages
        let root = chatRoot(messages: messages)
        let withCommandHandlers = applyCommandHandlers(to: root)
        return applyMacDropSupport(to: withCommandHandlers)
    }

    private func chatRoot(messages: [Message]) -> some View {
        let base = baseChatLayout(messages: messages)
        let presented = applyPresentationModifiers(to: base)
        return applyDialogAndAlertModifiers(to: presented)
    }

    private func baseChatLayout(messages: [Message]) -> some View {
        VStack(spacing: 0) {
            if !network.isConnected {
                offlineBanner
            }

            chatContent(messages: messages)

            inputBar
        }
        .background(Color.bgPrimary)
        #if os(macOS)
        .navigationTitle("SEER")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Stop streaming when this chat is torn down (e.g. the conversation is
        // deleted in the macOS sidebar while a response is in flight) so the
        // background task stops mutating a model that may be deleted.
        .onDisappear {
            if streaming.isStreaming {
                streaming.cancel(conversation: conversation, modelContext: modelContext)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarPrincipal
            }
            ToolbarItem(placement: .seerTrailing) {
                Button { showParameters = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(Color.textSecondary)
                        #if os(macOS)
                        .frame(minWidth: 26, minHeight: 26)
                        #endif
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .macPointingCursor()
                #endif
            }
            #if os(macOS)
            ToolbarItem(placement: .seerTrailing) {
                Button {
                    exportConversationMarkdown()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(Color.textSecondary)
                        .frame(minWidth: 26, minHeight: 26)
                }
                .buttonStyle(.plain)
                .macPointingCursor()
            }
            #else
            ToolbarItem(placement: .seerTrailing) {
                Button {
                    shareConversation()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(Color.textSecondary)
                }
                .disabled(conversation.messages.isEmpty)
            }
            #endif
        }
    }

    private func applyPresentationModifiers<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(onSelect: { model in
                    conversation.modelName = model.name
                    conversation.apiProvider = model.provider
                    do {
                        try modelContext.save()
                        showModelPicker = false
                    } catch {
                        streaming.error = "Failed to save selected model."
                    }
                })
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                #else
                .presentationBackground(Color.bgPrimary)
                #endif
                .macSheetFixedSize(SeerSheetSize.modelPicker)
            }
            .sheet(isPresented: $showParameters) {
                ParametersView(conversation: conversation)
                    #if os(macOS)
                    .presentationBackground(Color.bgPrimary)
                    #endif
                    .macSheetFixedSize(SeerSheetSize.parameters)
            }
            .sheet(isPresented: $showScaffoldLibrary) {
                ScaffoldLibraryView(
                    accountScopeKey: AccountScope.currentKey(),
                    onAttach: { scaffold in
                        attachScaffold(scaffold)
                    },
                    dismissOnAttach: true
                )
                #if os(macOS)
                .presentationBackground(Color.bgPrimary)
                #endif
                .macSheetFixedSize(SeerSheetSize.scaffoldLibrary)
            }
            .sheet(isPresented: $showGitHubBrowser) {
                GitHubContextPickerView { files in
                    attachGitHubContextFiles(files)
                }
                #if os(macOS)
                .presentationBackground(Color.bgPrimary)
                #endif
                .macSheetFixedSize(SeerSheetSize.githubContextPicker)
            }
            #if os(iOS)
            .sheet(item: $exportShareItem, onDismiss: {
                // Remove the temporary export file once the share sheet closes.
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(defaultExportFilename)
                try? FileManager.default.removeItem(at: tempURL)
            }) { item in
                ShareSheet(activityItems: [item.url])
                    .presentationDetents([.medium, .large])
            }
            #endif
            .onChange(of: streaming.error) { _, newError in
                if newError != nil {
                    Haptic.notification(.error)
                }
            }
            .onAppear {
                ensureBranchingStatePrepared()
                refreshActiveScaffoldNameFromStore()
                if conversation.messages.isEmpty && !conversation.modelName.isEmpty {
                    isInputFocused = true
                }
            }
            .onChange(of: conversation.activeScaffoldID) { _, _ in
                refreshActiveScaffoldNameFromStore()
            }
            .onChange(of: conversation.modelName) { _, newValue in
                if !newValue.isEmpty && conversation.messages.isEmpty {
                    isInputFocused = true
                }
            }
    }

    private func applyDialogAndAlertModifiers<Content: View>(to view: Content) -> some View {
        view
            .confirmationDialog(
                "Attach",
                isPresented: $showAttachmentOptions,
                titleVisibility: .visible
            ) {
                Button("Photo Library") {
                    showPhotoPicker = true
                }
                Button("Files") {
                    showFileImporter = true
                }
                Button("GitHub Repository") {
                    showGitHubBrowser = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Attach images, local text files, or GitHub repository files as context for your next message.")
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 5,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await importSelectedPhotos(newItems)
                    await MainActor.run {
                        selectedPhotoItems = []
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    .plainText, .utf8PlainText, .text, .sourceCode,
                    .json, .xml, .commaSeparatedText
                ],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await importFiles(urls) }
                case .failure(let error):
                    attachmentError = error.localizedDescription
                }
            }
            .alert("Attachment Error", isPresented: Binding(
                get: { attachmentError != nil },
                set: { _ in attachmentError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(attachmentError ?? "Unable to load attachment.")
            }
            .alert("Scaffold Error", isPresented: Binding(
                get: { scaffoldPersistenceError != nil },
                set: { _ in scaffoldPersistenceError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scaffoldPersistenceError ?? "Unable to update reasoning scaffold.")
            }
            .alert("Export Error", isPresented: Binding(
                get: { exportError != nil },
                set: { _ in exportError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "Unable to export conversation.")
            }
            .alert("Vision Model Recommended", isPresented: $showVisionModelWarning) {
                Button("Send Anyway") {
                    send(bypassVisionCheck: true)
                }
                Button("Choose Model") {
                    showModelPicker = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The selected model may not support image input. You can send anyway, choose a vision-capable model, or remove the image attachments.")
            }
    }

    @ViewBuilder
    private func applyCommandHandlers<Content: View>(to view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: AppCommand.sendMessage)) { _ in
                #if os(macOS)
                send()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCommand.quickModelSwitch)) { _ in
                #if os(macOS)
                showModelPicker = true
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCommand.exportConversation)) { _ in
                #if os(macOS)
                exportConversationMarkdown()
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCommand.previousBranch)) { _ in
                #if os(macOS)
                cycleBranch(direction: -1)
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: AppCommand.nextBranch)) { _ in
                #if os(macOS)
                cycleBranch(direction: 1)
                #endif
            }
    }

    @ViewBuilder
    private func applyMacDropSupport<Content: View>(to view: Content) -> some View {
        #if os(macOS)
        view
            .overlay {
                if isFileDropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.accentSoft.opacity(0.35))
                        )
                        .padding(10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isFileDropTargeted)
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $isFileDropTargeted,
                perform: handleDroppedFiles
            )
        #else
        view
        #endif
    }

    @ViewBuilder
    private func chatContent(messages: [Message]) -> some View {
        ZStack(alignment: .bottom) {
            GeometryReader { scrollGeo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if messages.isEmpty && !streaming.isStreaming {
                            VStack(spacing: 16) {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                // A send can fail before anything is persisted
                                // (e.g. the model-availability preflight) —
                                // surface it here too, or the typed prompt
                                // silently vanishes on a fresh chat.
                                if let error = streaming.error {
                                    errorBubble(error)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 24)
                                }
                                if let notice = streaming.notice, !notice.isEmpty {
                                    noticeBubble(notice)
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 24)
                                }
                            }
                            .frame(minHeight: scrollGeo.size.height - 1)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    let siblings = siblingsFor(message)
                                    let siblingIndex = siblings.firstIndex(where: { $0.id == message.id }) ?? 0
                                    MessageRow(
                                        message: message,
                                        chatMessageCount: messages.count,
                                        showsThinkingSection: shouldShowThinkingUI,
                                        siblingMessages: siblings,
                                        siblingIndex: siblingIndex,
                                        onEditPrompt: { selected in
                                            requestEditPrompt(for: selected)
                                        },
                                        onRegenerate: { selected in
                                            requestRegenerate(for: selected)
                                        },
                                        onSwitchBranch: { target in
                                            switchBranch(to: target)
                                        }
                                    )
                                        .id(message.id)
                                }

                                if streaming.isStreaming {
                                    if streaming.isExecutingTool {
                                        ToolExecutionIndicator(status: streaming.toolCallStatus)
                                            .id("toolExec")
                                    } else if hasVisibleStreamingPayload {
                                        VStack(alignment: .leading, spacing: 6) {
                                            streamingBubble
                                            streamingStats
                                        }
                                        .id("streaming")
                                    } else {
                                        TypingIndicator()
                                            .id("typing")
                                    }
                                }

                                if let error = streaming.error {
                                    errorBubble(error)
                                        .id("error")
                                }

                                if let notice = streaming.notice, !notice.isEmpty {
                                    noticeBubble(notice)
                                        .id("notice")
                                }

                                GeometryReader { anchorGeo in
                                    Color.clear
                                        .onAppear {
                                            updateScrollPosition(
                                                anchorMaxY: anchorGeo.frame(in: .named("chatScroll")).maxY
                                            )
                                        }
                                        .onChange(of: anchorGeo.frame(in: .named("chatScroll")).maxY) { _, newValue in
                                            updateScrollPosition(anchorMaxY: newValue)
                                        }
                                }
                                .frame(height: 1)
                                .id("bottomAnchor")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                    }
                    .coordinateSpace(name: "chatScroll")
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { _ in
                                if streaming.isStreaming {
                                    shouldAutoFollowStreaming = false
                                }
                            }
                    )
                    .onAppear {
                        updateScrollPosition(viewportHeight: scrollGeo.size.height)
                    }
                    .onChange(of: scrollGeo.size.height) { _, newHeight in
                        updateScrollPosition(viewportHeight: newHeight)
                    }
                    .onChange(of: messages.count) {
                        if isAtBottom {
                            scrollToBottom(proxy: proxy, messages: messages)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { hasNewMessage = true }
                        }
                    }
                    .onChange(of: streaming.streamingContent) {
                        autoFollowStreamingIfNeeded(proxy: proxy, messages: messages)
                        if !sentFirstTokenHaptic && !streaming.streamingContent.isEmpty {
                            sentFirstTokenHaptic = true
                            Haptic.notification(.success)
                        }
                    }
                    .onChange(of: streaming.streamingThinking) {
                        autoFollowStreamingIfNeeded(proxy: proxy, messages: messages)
                    }
                    .onChange(of: streaming.isStreaming) { _, isNow in
                        if isNow {
                            sentFirstTokenHaptic = false
                            shouldAutoFollowStreaming = isAtBottom
                            lastStreamingAutoScrollAt = .distantPast
                        } else {
                            shouldAutoFollowStreaming = true
                            if isAtBottom {
                                scrollToBottom(proxy: proxy, messages: messages)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if hasNewMessage && !isAtBottom {
                            Button {
                                withAnimation(.snappy(duration: 0.3)) {
                                    scrollToBottom(proxy: proxy, messages: messages)
                                    hasNewMessage = false
                                    isAtBottom = true
                                    shouldAutoFollowStreaming = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("NEW")
                                        .font(.appLabel(9))
                                        .tracking(2)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Capsule().fill(Color.accent.opacity(0.5)))
                                )
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                            }
                            #if os(macOS)
                            .buttonStyle(.plain)
                            .macHoverSurface(isHoveringNewBadge, radius: 24, fill: Color.white.opacity(0.06))
                            .macPointingCursor(isHoveringNewBadge)
                            .onHover { isHoveringNewBadge = $0 }
                            #endif
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 10, weight: .ultraLight))
            Text("OFFLINE")
                .font(.appLabel(10))
                .labelTracking()
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.danger.opacity(0.85))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: network.isConnected)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            if conversation.modelName.isEmpty {
                Image(systemName: "cpu")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.textTertiary)
                Text("Pick a model to begin")
                    .font(.app(15, weight: .light))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    showModelPicker = true
                } label: {
                    Text("CHOOSE MODEL")
                        .font(.appLabel(12))
                        .labelTracking()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(LinearGradient.accentGradient))
                }
                .padding(.top, 4)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(Color.accent.opacity(0.4))
                Text("Send a message to begin")
                    .font(.app(15, weight: .light))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Streaming

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if shouldShowThinkingUI, !streaming.streamingThinking.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                showStreamingThinking.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "brain")
                                    .font(.system(size: 11, weight: .ultraLight))
                                Group {
                                    if streaming.isThinking {
                                        Text("THINKING...")
                                            .font(.appLabel(10))
                                            .tracking(2)
                                            .shimmer()
                                    } else {
                                        Text("THINKING")
                                            .font(.appLabel(10))
                                            .tracking(2)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .medium))
                                    .rotationEffect(.degrees(showStreamingThinking ? 90 : 0))
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showStreamingThinking {
                            Text(verbatim: streaming.streamingThinking)
                                .font(.app(13))
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                    }
                    .background(Color.white.opacity(0.02))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: streaming.streamingContent.isEmpty ? 20 : 0,
                            bottomTrailingRadius: streaming.streamingContent.isEmpty ? 20 : 0,
                            topTrailingRadius: 20,
                            style: .continuous
                        )
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 20,
                            bottomLeadingRadius: streaming.streamingContent.isEmpty ? 20 : 0,
                            bottomTrailingRadius: streaming.streamingContent.isEmpty ? 20 : 0,
                            topTrailingRadius: 20,
                            style: .continuous
                        )
                        .stroke(Color.border, lineWidth: 0.5)
                    )
                }

                if !streaming.streamingContent.isEmpty {
                    let hasVisibleThinking = shouldShowThinkingUI && !streaming.streamingThinking.isEmpty
                    let contentShape = UnevenRoundedRectangle(
                        topLeadingRadius: hasVisibleThinking ? 0 : 20,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: hasVisibleThinking ? 0 : 20,
                        style: .continuous
                    )
                    Text(verbatim: streaming.streamingContent)
                        .font(.app(14))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        #if os(macOS)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                        #endif
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .assistantMaterialBubble(shape: contentShape)
                    }
            }
            #if os(macOS)
            .frame(maxWidth: 820, alignment: .leading)
            #endif
            Spacer(minLength: 48)
        }
        #if os(macOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    // MARK: - Streaming Stats

    private var streamingStats: some View {
        HStack(spacing: 8) {
            if shouldShowThinkingUI, !streaming.streamingThinking.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 8, weight: .ultraLight))
                    Text("\(streaming.streamingThinking.count) think chars")
                        .font(.app(10, weight: .medium).monospaced())
                }
            }

            if !streaming.streamingContent.isEmpty {
                HStack(spacing: 4) {
                    Text("\(streaming.streamingContent.count) chars")
                        .font(.app(10, weight: .medium).monospaced())
                    if streaming.tokenCount > 0 {
                        Text("·")
                            .font(.app(10))
                        Text("\(streaming.tokenCount) chunks")
                            .font(.app(10, weight: .medium).monospaced())
                    }
                    if streaming.tokensPerSecond > 0.5 {
                        Text("·")
                            .font(.app(10))
                        Text(String(format: "%.1f chunk/s", streaming.tokensPerSecond))
                            .font(.app(10, weight: .medium).monospaced())
                    }
                }
            }

            Spacer()
        }
        .foregroundStyle(Color.textTertiary)
        .padding(.leading, 4)
    }

    // MARK: - Error

    private func errorBubble(_ message: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(message)
                        .font(.app(13))
                }
                .foregroundStyle(Color.danger)

                // Recovery button
                if streaming.recoveryAction == .chooseModel, !streaming.isStreaming {
                    Button {
                        showModelPicker = true
                        streaming.error = nil
                        streaming.recoveryAction = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "cpu")
                                .font(.system(size: 10, weight: .ultraLight))
                            Text("CHOOSE MODEL")
                                .font(.appLabel(10))
                                .tracking(2)
                        }
                        .foregroundStyle(Color.accent)
                    }
                } else if streaming.canRetryLast, !streaming.isStreaming {
                    Button {
                        retryLast()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .ultraLight))
                            Text("RETRY")
                                .font(.appLabel(10))
                                .tracking(2)
                        }
                        .foregroundStyle(Color.accent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.danger.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.danger.opacity(0.1), lineWidth: 0.5)
                    )
            )
            // Tap to dismiss
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    streaming.error = nil
                    streaming.recoveryAction = nil
                }
            }
            Spacer()
        }
    }

    private func noticeBubble(_ message: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12, weight: .ultraLight))
                        .foregroundStyle(Color.accent)
                    Text(message)
                        .font(.app(12))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentSoft.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.border, lineWidth: 0.5)
                    )
            )
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    streaming.notice = nil
                }
            }
            Spacer()
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 0.5)

            VStack(spacing: 8) {
                if AppConfig.reasoningScaffoldsEnabled, let scaffoldName = activeScaffoldDisplayName {
                    ScaffoldChip(
                        name: scaffoldName,
                        onSwap: { showScaffoldLibrary = true },
                        onClear: { clearActiveScaffold() }
                    )
                }

                if hasPendingAttachments {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(pendingImageAttachments.enumerated()), id: \.element.id) { idx, attachment in
                                attachmentChip(
                                    icon: "photo",
                                    label: "Image \(idx + 1) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))"
                                ) {
                                    pendingImageAttachments.removeAll { $0.id == attachment.id }
                                }
                            }
                            ForEach(pendingFileAttachments) { file in
                                attachmentChip(
                                    icon: "doc.text",
                                    label: fileAttachmentLabel(file)
                                ) {
                                    pendingFileAttachments.removeAll { $0.id == file.id }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                        showAttachmentOptions = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(
                                Circle()
                                    .fill(Color.accentSoft)
                                    .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .macPointingCursor()
                    #endif
                    .disabled(streaming.isStreaming)
                    .accessibilityLabel("Add attachment")
                    .accessibilityHint("Attach photos, local files, or GitHub repository files to your next message")

                    if AppConfig.reasoningScaffoldsEnabled {
                        Button {
                            showScaffoldLibrary = true
                        } label: {
                            Image(systemName: "brain")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.accent)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(
                                    Circle()
                                        .fill(Color.accentSoft)
                                        .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .macPointingCursor()
                        #endif
                        .disabled(streaming.isStreaming)
                        .accessibilityLabel("Reasoning scaffold")
                        .accessibilityHint("Choose or change the reasoning scaffold for this chat")
                    }

                    TextField("", text: $input, prompt: Text(inputPlaceholder).foregroundStyle(Color.textTertiary), axis: .vertical)
                        .font(.app(15))
                        .lineLimit(1...6)
                        .foregroundStyle(Color.textPrimary)
                        .focused($isInputFocused)
                        #if os(macOS)
                        .textFieldStyle(.plain)
                        #endif
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.bgSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.borderLight, lineWidth: 0.5)
                                )
                        )
                        .onSubmit { send() }
                        .accessibilityLabel("Message input")
                        .accessibilityHint("Type your message")

                    #if os(iOS)
                    if dictation.isAvailable {
                        Button {
                            toggleDictation()
                        } label: {
                            Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(dictation.isRecording ? .white : Color.accent)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(
                                    Circle()
                                        .fill(dictation.isRecording ? AnyShapeStyle(Color.danger) : AnyShapeStyle(Color.accentSoft))
                                        .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(streaming.isStreaming)
                        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start voice dictation")
                    }
                    #endif

                    if streaming.isStreaming {
                        Button {
                            Haptic.impact(.medium)
                            streaming.cancel(conversation: conversation, modelContext: modelContext)
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .ultraLight))
                                .foregroundStyle(.white)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(Circle().fill(Color.danger))
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        .macPointingCursor()
                        #endif
                        .accessibilityLabel("Stop generation")
                    } else {
                        Button(action: { send() }) {
                            Image(systemName: canSend ? "arrow.up" : (network.isConnected ? "arrow.up" : "wifi.slash"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(
                                    Circle().fill(canSend ? LinearGradient.accentGradient : LinearGradient(colors: [Color.bgTertiary], startPoint: .top, endPoint: .bottom))
                                )
                        }
                        .disabled(!canSend)
                        #if os(macOS)
                        .buttonStyle(.plain)
                        .macPointingCursor()
                        #endif
                        .accessibilityLabel("Send message")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bgPrimary)
            #if os(iOS)
            .onChange(of: dictation.transcript) { _, newValue in
                applyDictation(newValue)
            }
            .onDisappear { dictation.stop() }
            .alert("Dictation", isPresented: Binding(
                get: { dictation.errorMessage != nil },
                set: { _ in dictation.errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dictation.errorMessage ?? "")
            }
            #endif
        }
    }

    #if os(iOS)
    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
        } else {
            dictationBaseText = input.trimmingCharacters(in: .whitespacesAndNewlines)
            isInputFocused = false
            Haptic.impact()
            dictation.start()
        }
    }

    /// Mirror the live transcript into the composer, preserving any text that
    /// was already typed before dictation began.
    private func applyDictation(_ transcript: String) {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if dictationBaseText.isEmpty {
            input = spoken
        } else if spoken.isEmpty {
            input = dictationBaseText
        } else {
            input = dictationBaseText + " " + spoken
        }
    }
    #endif

    @ViewBuilder
    private var toolbarPrincipal: some View {
        #if os(macOS)
        HStack(spacing: 8) {
            Text("SEER")
                .font(.appLabel(10))
                .labelTracking()
                .foregroundStyle(Color.textSecondary)
            if !conversation.modelName.isEmpty {
                Text(conversation.modelName.uppercased())
                    .font(.appLabel(9))
                    .luxuryTracking()
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentSoft))
                    .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
                    .lineLimit(1)
            }
        }
        #else
        if !conversation.modelName.isEmpty {
            Text(conversation.modelName.uppercased())
                .font(.appLabel(10))
                .luxuryTracking()
                .foregroundStyle(Color.accent)
        }
        #endif
    }

    // MARK: - Helpers

    private var inputPlaceholder: String {
        if conversation.modelName.isEmpty { return "Message" }
        // Use the display-friendly part (e.g. "kimi-k2-thinking" → "Kimi K2")
        let name = conversation.modelName
            .split(separator: ":").first.map(String.init) ?? conversation.modelName
        return "Message \(name)"
    }

    private var activeScaffoldDisplayName: String? {
        let trimmed = conversation.activeScaffoldName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var canSend: Bool {
        (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasPendingAttachments)
        && !streaming.isStreaming
        && !conversation.modelName.isEmpty
        && network.isConnected
    }

    private var hasPendingAttachments: Bool {
        !pendingImageAttachments.isEmpty || !pendingFileAttachments.isEmpty
    }

    private var shouldShowThinkingUI: Bool {
        SeerAssistantProfile.shouldEnableThinking(
            for: conversation.modelName,
            mode: conversation.thinkingMode
        )
    }

    private var hasVisibleStreamingPayload: Bool {
        !streaming.streamingContent.isEmpty
        || (shouldShowThinkingUI && !streaming.streamingThinking.isEmpty)
    }

    private func ensureBranchingStatePrepared() {
        guard conversation.prepareBranchingState() else { return }

        conversation.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            streaming.notice = "Branch state could not be fully persisted."
        }
    }

    private func requestEditPrompt(for message: Message) {
        guard !streaming.isStreaming else { return }
        guard message.role == "user" else { return }

        ensureBranchingStatePrepared()
        forkParentID = message.parentID

        let (restoredPrompt, _) = splitDisplayContent(message.content)
        let restoredImages = decodeImages(from: message).map { base64 in
            PendingImageAttachment(
                base64: base64,
                byteCount: Data(base64Encoded: base64)?.count ?? 0
            )
        }

        input = restoredPrompt
        pendingImageAttachments = restoredImages
        pendingFileAttachments = []
        isInputFocused = true

        if hasAttachedFiles(in: message.attachmentRequestContent) {
            streaming.notice = "Prompt restored. Reattach files before sending."
        } else {
            streaming.notice = "Prompt restored for editing."
        }
        Haptic.selection()
    }

    private func requestRegenerate(for message: Message) {
        guard !streaming.isStreaming else { return }
        guard message.role == "assistant" else { return }

        ensureBranchingStatePrepared()

        guard let sourceUserMessage = nearestAncestorUserMessage(from: message.parentID) else {
            streaming.notice = "Could not find the related user prompt for regeneration."
            return
        }

        let (userText, attachmentSummary) = splitDisplayContent(sourceUserMessage.content)
        let requestContent = sourceUserMessage.attachmentRequestContent ?? sourceUserMessage.content
        let images = decodeImages(from: sourceUserMessage)

        // Abandon any in-progress prompt edit — a later send must not fork at
        // the stale edit point.
        forkParentID = nil
        input = ""
        pendingImageAttachments.removeAll()
        pendingFileAttachments.removeAll()
        Haptic.impact()

        Task {
            var tools: [ChatTool] = visualizationsEnabled ? VisualsToolkit.tools : []
            tools.append(contentsOf: AssistantToolkit.tools(webAccessEnabled: webAccessEnabled))
            if project != nil { tools.append(contentsOf: CodeToolkit.tools) }
            var manager: AnyObject? = nil
            #if os(macOS)
            if let mcpTools = mcpManager.ollamaTools() {
                tools.append(contentsOf: mcpTools)
            }
            manager = mcpManager
            #endif
            await streaming.sendMessage(
                content: userText,
                requestContent: requestContent,
                imageBase64s: images,
                attachmentSummary: attachmentSummary,
                persistUserMessage: false,
                parentMessageID: sourceUserMessage.id,
                tools: tools.isEmpty ? nil : tools,
                mcpManager: manager,
                project: project,
                extraSystemPrompt: projectContextPrompt,
                conversation: conversation,
                modelContext: modelContext
            )
        }
    }

    private func siblingsFor(_ message: Message) -> [Message] {
        guard conversation.activeLeafID != nil else { return [] }
        let parentID = message.parentID
        return conversation.messages
            .filter { $0.parentID == parentID && $0.role == message.role }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func cycleBranch(direction: Int) {
        ensureBranchingStatePrepared()
        guard conversation.activeLeafID != nil else { return }

        let branch = sortedMessages
        // Find the deepest message in the active branch that has siblings
        for message in branch.reversed() {
            let siblings = siblingsFor(message)
            guard siblings.count > 1 else { continue }
            guard let currentIndex = siblings.firstIndex(where: { $0.id == message.id }) else { continue }

            let nextIndex: Int
            if direction > 0 {
                nextIndex = currentIndex < siblings.count - 1 ? currentIndex + 1 : 0
            } else {
                nextIndex = currentIndex > 0 ? currentIndex - 1 : siblings.count - 1
            }
            switchBranch(to: siblings[nextIndex])
            return
        }
    }

    private func switchBranch(to target: Message) {
        forkParentID = nil
        let leafID = conversation.findLeaf(from: target.id)
        conversation.activeLeafID = leafID
        do {
            try modelContext.save()
        } catch {
            streaming.notice = "Branch state could not be fully persisted."
        }
    }

    private func nearestAncestorUserMessage(from messageID: UUID?) -> Message? {
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

    private func splitDisplayContent(_ content: String) -> (userText: String, attachmentSummary: String?) {
        guard let markerRange = content.range(of: "\n\nAttachments:") else {
            return (content, nil)
        }

        let userText = String(content[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryStart = content.index(markerRange.lowerBound, offsetBy: 2)
        let summary = String(content[summaryStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (userText, summary.isEmpty ? nil : summary)
    }

    private func hasAttachedFiles(in requestContent: String?) -> Bool {
        guard let requestContent else { return false }
        return requestContent.contains("--- Begin Attached Files ---")
    }

    private func decodeImages(from message: Message) -> [String] {
        guard message.role == "user",
              let json = message.imageBase64sJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func attachScaffold(_ scaffold: ReasoningScaffold) {
        conversation.activeScaffoldID = scaffold.id.uuidString
        conversation.activeScaffoldName = scaffold.name
        conversation.updatedAt = Date()
        do {
            try modelContext.save()
            AppTelemetry.track("scaffold_attached", metadata: ["id": scaffold.id.uuidString])
            Haptic.selection()
        } catch {
            scaffoldPersistenceError = "Failed to attach reasoning scaffold."
        }
    }

    private func clearActiveScaffold() {
        let hadScaffold = (conversation.activeScaffoldID?.isEmpty == false)
            || (conversation.activeScaffoldName?.isEmpty == false)
        conversation.activeScaffoldID = nil
        conversation.activeScaffoldName = nil
        conversation.updatedAt = Date()
        do {
            try modelContext.save()
            if hadScaffold {
                AppTelemetry.track("scaffold_cleared", metadata: ["reason": "manual"])
            }
            Haptic.selection()
        } catch {
            scaffoldPersistenceError = "Failed to clear reasoning scaffold."
        }
    }

    private func refreshActiveScaffoldNameFromStore() {
        guard AppConfig.reasoningScaffoldsEnabled else { return }
        let resolution = ReasoningScaffoldResolver.resolveActiveScaffold(
            for: conversation,
            in: modelContext
        )
        if resolution.cleared {
            streaming.notice = "Active reasoning scaffold was cleared for this account."
        }
    }

    private func send(bypassVisionCheck: Bool = false) {
        #if os(iOS)
        dictation.stop()
        #endif
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || hasPendingAttachments else { return }

        if conversation.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            streaming.notice = "Choose a model before sending."
            showModelPicker = true
            return
        }

        guard network.isConnected else {
            streaming.error = OllamaAPIError.offline.userMessage
            return
        }

        if !bypassVisionCheck,
           !pendingImageAttachments.isEmpty,
           !isLikelyVisionModel(conversation.modelName) {
            showVisionModelWarning = true
            return
        }

        ensureBranchingStatePrepared()
        let attachmentSummary = makeAttachmentSummary()
        let requestContent = makeRequestContent(userText: text)
        let imageBase64s = pendingImageAttachments.map(\.base64)
        let parentForNewMessage = forkParentID ?? conversation.activeLeafID

        input = ""
        forkParentID = nil
        pendingImageAttachments.removeAll()
        pendingFileAttachments.removeAll()

        Haptic.impact()
        Task {
            var tools: [ChatTool] = visualizationsEnabled ? VisualsToolkit.tools : []
            tools.append(contentsOf: AssistantToolkit.tools(webAccessEnabled: webAccessEnabled))
            if project != nil { tools.append(contentsOf: CodeToolkit.tools) }
            var manager: AnyObject? = nil
            #if os(macOS)
            if let mcpTools = mcpManager.ollamaTools() {
                tools.append(contentsOf: mcpTools)
            }
            manager = mcpManager
            #endif
            await streaming.sendMessage(
                content: text,
                requestContent: requestContent,
                imageBase64s: imageBase64s,
                attachmentSummary: attachmentSummary,
                parentMessageID: parentForNewMessage,
                tools: tools.isEmpty ? nil : tools,
                mcpManager: manager,
                project: project,
                extraSystemPrompt: projectContextPrompt,
                conversation: conversation,
                modelContext: modelContext
            )
        }
    }

    private func retryLast() {
        streaming.error = nil

        Haptic.impact()
        Task {
            var tools: [ChatTool] = visualizationsEnabled ? VisualsToolkit.tools : []
            tools.append(contentsOf: AssistantToolkit.tools(webAccessEnabled: webAccessEnabled))
            if project != nil { tools.append(contentsOf: CodeToolkit.tools) }
            var manager: AnyObject? = nil
            #if os(macOS)
            if let mcpTools = mcpManager.ollamaTools() {
                tools.append(contentsOf: mcpTools)
            }
            manager = mcpManager
            #endif
            await streaming.retryLast(tools: tools.isEmpty ? nil : tools, mcpManager: manager, project: project, extraSystemPrompt: projectContextPrompt, conversation: conversation, modelContext: modelContext)
        }
    }

    private func autoFollowStreamingIfNeeded(proxy: ScrollViewProxy, messages: [Message]) {
        guard streaming.isStreaming, isAtBottom, shouldAutoFollowStreaming else { return }

        let now = Date()
        guard Self.shouldTriggerStreamingAutoScroll(
            now: now,
            lastAutoScrollAt: lastStreamingAutoScrollAt,
            interval: Self.streamingAutoScrollThrottleInterval
        ) else {
            return
        }
        lastStreamingAutoScrollAt = now
        scrollToBottom(proxy: proxy, messages: messages)
    }

    nonisolated static func shouldTriggerStreamingAutoScroll(
        now: Date,
        lastAutoScrollAt: Date,
        interval: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(lastAutoScrollAt) >= interval
    }

    private func updateScrollPosition(anchorMaxY: CGFloat? = nil, viewportHeight: CGFloat? = nil) {
        if let anchorMaxY {
            bottomAnchorMaxY = anchorMaxY
        }
        if let viewportHeight {
            scrollViewportHeight = viewportHeight
        }

        guard scrollViewportHeight > 0 else { return }

        let bottomThreshold: CGFloat = 48
        let nowAtBottom = bottomAnchorMaxY <= scrollViewportHeight + bottomThreshold
        if nowAtBottom != isAtBottom {
            isAtBottom = nowAtBottom
        }
        if nowAtBottom {
            shouldAutoFollowStreaming = true
        }
        if nowAtBottom && hasNewMessage {
            hasNewMessage = false
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, messages: [Message]) {
        if streaming.isStreaming {
            if !streaming.streamingContent.isEmpty || !streaming.streamingThinking.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else {
                proxy.scrollTo("typing", anchor: .bottom)
            }
        } else if let last = messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func attachmentChip(icon: String, label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .ultraLight))
            Text(label)
                .font(.app(11))
                .lineLimit(1)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.surface)
                .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
        )
    }

    private func fileAttachmentLabel(_ file: PendingFileAttachment) -> String {
        if file.originalCharacterCount > file.content.count {
            return "\(file.name) · truncated \(file.content.count)/\(file.originalCharacterCount) chars"
        }
        return "\(file.name) · \(file.content.count) chars"
    }

    #if os(macOS)
    private static let dropAllowedExtensions: Set<String> = [
        "swift", "py", "js", "ts", "json", "yaml", "yml",
        "md", "txt", "log", "csv", "sh", "html", "css"
    ]
    private static let maxDroppedFileBytes = 100 * 1024

    private func handleDroppedFiles(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        for provider in fileProviders {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    Task { @MainActor in
                        attachmentError = "Failed to load dropped file: \(error.localizedDescription)"
                    }
                    return
                }

                guard let url = droppedFileURL(from: item) else {
                    Task { @MainActor in
                        attachmentError = "Dropped item is not a valid file URL."
                    }
                    return
                }

                Task {
                    await appendDroppedFileToInput(from: url)
                }
            }
        }

        return true
    }

    private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let string = item as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func appendDroppedFileToInput(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()
        guard Self.dropAllowedExtensions.contains(ext) else {
            await MainActor.run {
                attachmentError = "Unsupported dropped file type: .\(ext)"
            }
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maxDroppedFileBytes else {
                await MainActor.run {
                    attachmentError = "\(url.lastPathComponent) exceeds 100KB and was not added."
                }
                return
            }

            guard let decoded = decodeTextFile(data: data) else {
                await MainActor.run {
                    attachmentError = "Unsupported file encoding for \(url.lastPathComponent)."
                }
                return
            }

            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let block = "```\(url.lastPathComponent)\n\(trimmed)\n```"
            await MainActor.run {
                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    input = block
                } else {
                    input += "\n\n" + block
                }
                isInputFocused = true
            }
        } catch {
            await MainActor.run {
                attachmentError = "Failed to read \(url.lastPathComponent)."
            }
        }
    }

    private func exportConversationMarkdown() {
        Task { @MainActor in
            do {
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = defaultExportFilename
                if let markdownType = UTType(filenameExtension: "md") {
                    panel.allowedContentTypes = [markdownType]
                } else {
                    panel.allowedContentTypes = [.plainText]
                }

                let response = panel.runModal()
                guard response == .OK, let destinationURL = panel.url else { return }

                try markdownExportContent.write(to: destinationURL, atomically: true, encoding: .utf8)
                Haptic.notification(.success)
            } catch {
                exportError = error.localizedDescription
                Haptic.notification(.error)
            }
        }
    }
    #endif

    private var defaultExportFilename: String {
        let raw = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = raw.isEmpty ? "Conversation" : raw
        let sanitized = base
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        return "\(sanitized).md"
    }

    private var markdownExportContent: String {
        var content = "# \(conversation.title)\n"
        content += "**Model:** \(conversation.modelName.isEmpty ? "None" : conversation.modelName)\n\n"

        for message in sortedMessages {
            let roleLabel: String
            switch message.role.lowercased() {
            case "user":
                roleLabel = "User"
            case "assistant":
                roleLabel = "Assistant"
            default:
                roleLabel = message.role.capitalized
            }

            content += "## \(roleLabel)\n\(message.content)\n\n"

            let thinking = message.thinkingContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !thinking.isEmpty {
                content += "<details><summary>Thinking</summary>\n\(thinking)\n</details>\n\n"
            }
        }

        return content
    }

    #if os(iOS)
    /// Writes the conversation as a Markdown file to a temp location and presents
    /// the iOS share sheet so it can be saved to Files, messaged, mailed, etc.
    private func shareConversation() {
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(defaultExportFilename)
            try markdownExportContent.write(to: url, atomically: true, encoding: .utf8)
            exportShareItem = ExportShareItem(url: url)
            Haptic.impact()
        } catch {
            exportError = error.localizedDescription
            Haptic.notification(.error)
        }
    }
    #endif

    private func makeAttachmentSummary() -> String? {
        guard hasPendingAttachments else { return nil }

        var components: [String] = []
        if !pendingImageAttachments.isEmpty {
            components.append("\(pendingImageAttachments.count) image\(pendingImageAttachments.count == 1 ? "" : "s")")
        }
        if !pendingFileAttachments.isEmpty {
            let names = pendingFileAttachments.map(\.name).joined(separator: ", ")
            components.append("\(pendingFileAttachments.count) file\(pendingFileAttachments.count == 1 ? "" : "s"): \(names)")
        }
        return "Attachments: " + components.joined(separator: " · ")
    }

    private func makeRequestContent(userText: String) -> String {
        var body = userText
        if body.isEmpty {
            if !pendingImageAttachments.isEmpty && pendingFileAttachments.isEmpty {
                body = "Please analyze the attached image(s)."
            } else if pendingImageAttachments.isEmpty && !pendingFileAttachments.isEmpty {
                body = "Please analyze the attached file(s)."
            } else {
                body = "Please analyze the attached image(s) and file(s)."
            }
        }

        guard !pendingFileAttachments.isEmpty else { return body }

        let sections = pendingFileAttachments.map { file in
            """
            ## Attached file: \(file.name)
            ```
            \(file.content)
            ```
            """
        }.joined(separator: "\n\n")

        return """
        \(body)

        --- Begin Attached Files ---
        \(sections)
        --- End Attached Files ---
        """
    }

    private func isLikelyVisionModel(_ modelName: String) -> Bool {
        let lower = modelName.lowercased()
        let tokens = Set(
            lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        )
        if tokens.contains("vision")
            || tokens.contains("vl")
            || tokens.contains("llava")
            || tokens.contains("moondream")
            || tokens.contains("multimodal") {
            return true
        }

        return lower.contains("qwen-vl")
            || lower.contains("qwen2-vl")
            || lower.contains("qwen2.5-vl")
            || lower.contains("internvl")
            || lower.contains("minicpm-v")
            || lower.contains("minicpmv")
            || lower.contains("gemma3")
            || lower.contains("mistral-small3")
            || lower.contains("llama4")
            || lower.contains("pixtral")
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        let existing = pendingImageAttachments.count
        let availableSlots = max(0, 5 - existing)
        if availableSlots == 0 {
            await MainActor.run {
                attachmentError = "You can attach up to 5 images per message."
            }
            return
        }

        if items.count > availableSlots {
            await MainActor.run {
                attachmentError = "You can attach up to 5 images per message. Only the first \(availableSlots) selected image\(availableSlots == 1 ? "" : "s") will be attached."
            }
        }

        for item in items.prefix(availableSlots) {
            do {
                guard let originalData = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        attachmentError = "One or more images couldn't be loaded."
                    }
                    continue
                }
                let preparedData = normalizedImageData(from: originalData)
                let base64 = preparedData.base64EncodedString()

                await MainActor.run {
                    pendingImageAttachments.append(
                        PendingImageAttachment(base64: base64, byteCount: preparedData.count)
                    )
                }
            } catch {
                await MainActor.run {
                    attachmentError = "Failed to load one or more images."
                }
            }
        }
    }

    private func importFiles(_ urls: [URL]) async {
        let maxCharacters = 18_000
        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let data = try Data(contentsOf: url)
                guard let decoded = decodeTextFile(data: data) else {
                    await MainActor.run {
                        attachmentError = "Unsupported file encoding for \(url.lastPathComponent)."
                    }
                    continue
                }

                let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let originalCount = trimmed.count
                let clipped = originalCount > maxCharacters ? String(trimmed.prefix(maxCharacters)) : trimmed
                let content: String
                if originalCount > maxCharacters {
                    content = clipped + "\n\n[Truncated to \(maxCharacters) characters]"
                } else {
                    content = clipped
                }

                await MainActor.run {
                    pendingFileAttachments.append(
                        PendingFileAttachment(
                            name: url.lastPathComponent,
                            content: content,
                            originalCharacterCount: originalCount
                        )
                    )
                }
            } catch {
                await MainActor.run {
                    attachmentError = "Failed to read \(url.lastPathComponent)."
                }
            }
        }
    }

    private func attachGitHubContextFiles(_ files: [GitHubContextFile]) {
        guard !files.isEmpty else { return }
        for file in files {
            pendingFileAttachments.append(
                PendingFileAttachment(
                    name: file.name,
                    content: file.content,
                    originalCharacterCount: file.originalCharacterCount
                )
            )
        }
        Haptic.selection()
    }

    private func decodeTextFile(data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        if let isoLatin1 = String(data: data, encoding: .isoLatin1) { return isoLatin1 }
        return nil
    }

    private func normalizedImageData(from data: Data) -> Data {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return data }
        let resized = resizeImageIfNeeded(image, maxDimension: 1600)
        return resized.jpegData(compressionQuality: 0.82) ?? data
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return data }
        let resized = resizeImageIfNeeded(image, maxDimension: 1600)
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return data }
        return jpeg
        #else
        return data
        #endif
    }

    #if os(iOS)
    private func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }

        let scale = maxDimension / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #elseif os(macOS)
    private func resizeImageIfNeeded(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }

        let scale = maxDimension / largest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: target),
                   from: CGRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
    #endif
}

#if os(iOS)
/// Identifiable wrapper so the exported file URL can drive `.sheet(item:)`.
private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Thin SwiftUI bridge to `UIActivityViewController` for the iOS share sheet.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
