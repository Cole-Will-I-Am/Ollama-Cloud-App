import SwiftUI
import SwiftData
import MarkdownUI

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

            ZStack(alignment: .bottom) {
                GeometryReader { scrollGeo in
                    ScrollViewReader { proxy in
                        ScrollView {
                            if messages.isEmpty && !streaming.isStreaming {
                                emptyState
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

                                    // Bottom anchor for scroll detection
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
                            // Success haptic on first token arrival
                            if !sentFirstTokenHaptic && !streaming.streamingContent.isEmpty {
                                sentFirstTokenHaptic = true
                                Haptic.notification(.success)
                            }
                        }
                        .onChange(of: streaming.isStreaming) { _, isNow in
                            if isNow { sentFirstTokenHaptic = false }
                        }
                        .overlay(alignment: .bottom) {
                            // "New Messages" floating button
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
        .onChange(of: streaming.error) { _, newError in
            if newError != nil {
                Haptic.notification(.error)
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
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
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

                // Retry button
                if let lastContent = streaming.lastSentContent, !streaming.isStreaming {
                    Button {
                        retry(content: lastContent)
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
                }
            }
            Spacer()
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 0.5)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $input, prompt: Text(inputPlaceholder).foregroundStyle(Color.textTertiary), axis: .vertical)
                    .font(.app(15))
                    .lineLimit(1...6)
                    .foregroundStyle(Color.textPrimary)
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

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !streaming.isStreaming
        && !conversation.modelName.isEmpty
        && network.isConnected
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !conversation.modelName.isEmpty else { return }
        input = ""

        Haptic.impact()
        streaming.sendMessage(content: text, conversation: conversation, modelContext: modelContext)
    }

    private func retry(content: String) {
        streaming.error = nil

        Haptic.impact()
        streaming.sendMessage(content: content, conversation: conversation, modelContext: modelContext)
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
}
