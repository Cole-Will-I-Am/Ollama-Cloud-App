import SwiftUI
import SwiftData
import MarkdownUI
import PhotosUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var network: NetworkMonitor
    @Bindable var conversation: Conversation
    @StateObject private var streaming = StreamingChatService()
    @State private var input = ""
    @State private var showModelPicker = false
    @State private var showParameters = false
    @State private var showStreamingThinking = true
    @State private var isAtBottom = true
    @State private var hasNewMessage = false
    @State private var sentFirstTokenHaptic = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var bottomAnchorMaxY: CGFloat = 0
    @FocusState private var isInputFocused: Bool
    @State private var showAttachmentOptions = false
    @State private var showScaffoldLibrary = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingImageAttachments: [PendingImageAttachment] = []
    @State private var pendingFileAttachments: [PendingFileAttachment] = []
    @State private var attachmentError: String?
    @State private var scaffoldPersistenceError: String?
    @State private var showVisionModelWarning = false

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
        conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let messages = sortedMessages
        VStack(spacing: 0) {
            // Offline banner
            if !network.isConnected {
                offlineBanner
            }

            chatContent(messages: messages)

            inputBar
        }
        .background(Color.bgPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if !conversation.modelName.isEmpty {
                    Text(conversation.modelName.uppercased())
                        .font(.appLabel(10))
                        .luxuryTracking()
                        .foregroundStyle(Color.accent)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showParameters = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView { model in
                conversation.modelName = model.name
                do {
                    try modelContext.save()
                    showModelPicker = false
                } catch {
                    streaming.error = "Failed to save selected model."
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showParameters) {
            ParametersView(conversation: conversation)
        }
        .sheet(isPresented: $showScaffoldLibrary) {
            ScaffoldLibraryView(
                accountScopeKey: AccountScope.currentKey(),
                onAttach: { scaffold in
                    attachScaffold(scaffold)
                },
                dismissOnAttach: true
            )
        }
        .onChange(of: streaming.error) { _, newError in
            if newError != nil {
                Haptic.notification(.error)
            }
        }
        .onAppear {
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
            Button("Cancel", role: .cancel) {}
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
        .alert("Vision Model Recommended", isPresented: $showVisionModelWarning) {
            Button("Choose Model") {
                showModelPicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The selected model may not support image input. Choose a vision-capable model or remove image attachments.")
        }
    }

    @ViewBuilder
    private func chatContent(messages: [Message]) -> some View {
        ZStack(alignment: .bottom) {
            GeometryReader { scrollGeo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if messages.isEmpty && !streaming.isStreaming {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: scrollGeo.size.height - 1)
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    MessageRow(message: message)
                                        .id(message.id)
                                }

                                if streaming.isStreaming {
                                    if !streaming.streamingThinking.isEmpty || !streaming.streamingContent.isEmpty {
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
                        if isAtBottom {
                            scrollToBottom(proxy: proxy, messages: messages)
                        }
                        if !sentFirstTokenHaptic && !streaming.streamingContent.isEmpty {
                            sentFirstTokenHaptic = true
                            Haptic.notification(.success)
                        }
                    }
                    .onChange(of: streaming.isStreaming) { _, isNow in
                        if isNow { sentFirstTokenHaptic = false }
                    }
                    .overlay(alignment: .bottom) {
                        if hasNewMessage && !isAtBottom {
                            Button {
                                withAnimation(.snappy(duration: 0.3)) {
                                    scrollToBottom(proxy: proxy, messages: messages)
                                    hasNewMessage = false
                                    isAtBottom = true
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

    // Markdown rendering handled by MarkdownUI

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                if !streaming.streamingThinking.isEmpty {
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
                            Markdown(streaming.streamingThinking)
                                .markdownTheme(.seerThinking)
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
                    let contentShape = UnevenRoundedRectangle(
                        topLeadingRadius: streaming.streamingThinking.isEmpty ? 20 : 0,
                        bottomLeadingRadius: 20,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: streaming.streamingThinking.isEmpty ? 20 : 0,
                        style: .continuous
                    )
                    Markdown(streaming.streamingContent)
                        .markdownTheme(.seerAssistant)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .assistantMaterialBubble(shape: contentShape)
                    }
            }
            Spacer(minLength: 48)
        }
    }

    // MARK: - Streaming Stats

    private var streamingStats: some View {
        HStack(spacing: 8) {
            if !streaming.streamingThinking.isEmpty {
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
                                    label: "\(file.name) · \(file.content.count) chars"
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
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(Color.accentSoft)
                                    .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(streaming.isStreaming)

                    if AppConfig.reasoningScaffoldsEnabled {
                        Button {
                            showScaffoldLibrary = true
                        } label: {
                            Image(systemName: "brain")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.accent)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(Color.accentSoft)
                                        .overlay(Circle().stroke(Color.border, lineWidth: 0.5))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(streaming.isStreaming)
                    }

                    TextField("", text: $input, prompt: Text(inputPlaceholder).foregroundStyle(Color.textTertiary), axis: .vertical)
                        .font(.app(15))
                        .lineLimit(1...6)
                        .foregroundStyle(Color.textPrimary)
                        .focused($isInputFocused)
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

                    if streaming.isStreaming {
                        Button {
                            Haptic.impact(.medium)
                            streaming.cancel(conversation: conversation, modelContext: modelContext)
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .ultraLight))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.danger))
                        }
                    } else {
                        Button(action: send) {
                            Image(systemName: canSend ? "arrow.up" : (network.isConnected ? "arrow.up" : "wifi.slash"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(
                                    Circle().fill(canSend ? LinearGradient.accentGradient : LinearGradient(colors: [Color.bgTertiary], startPoint: .top, endPoint: .bottom))
                                )
                        }
                        .disabled(!canSend)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bgPrimary)
        }
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

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!text.isEmpty || hasPendingAttachments), !conversation.modelName.isEmpty else { return }
        if !pendingImageAttachments.isEmpty && !isLikelyVisionModel(conversation.modelName) {
            showVisionModelWarning = true
            return
        }

        let attachmentSummary = makeAttachmentSummary()
        let requestContent = makeRequestContent(userText: text)
        let imageBase64s = pendingImageAttachments.map(\.base64)

        input = ""
        pendingImageAttachments.removeAll()
        pendingFileAttachments.removeAll()

        Haptic.impact()
        Task {
            await streaming.sendMessage(
                content: text,
                requestContent: requestContent,
                imageBase64s: imageBase64s,
                attachmentSummary: attachmentSummary,
                conversation: conversation,
                modelContext: modelContext
            )
        }
    }

    private func retryLast() {
        streaming.error = nil

        Haptic.impact()
        Task {
            await streaming.retryLast(conversation: conversation, modelContext: modelContext)
        }
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
            [Attached File: \(file.name)]
            \(file.content)
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
        return lower.contains("vision")
            || lower.contains("llava")
            || lower.contains("moondream")
            || lower.contains("vl")
            || lower.contains("multimodal")
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

        for item in items.prefix(availableSlots) {
            do {
                guard let originalData = try await item.loadTransferable(type: Data.self) else { continue }
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
    #endif
}
