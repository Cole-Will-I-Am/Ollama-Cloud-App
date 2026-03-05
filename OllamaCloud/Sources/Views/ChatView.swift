import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var network: NetworkMonitor
    @Bindable var conversation: Conversation
    @StateObject private var streaming = StreamingChatService()
    @State private var input = ""
    @State private var showModelPicker = false
    @State private var showParameters = false
    @State private var showStreamingThinking = true

    private var sortedMessages: [Message] {
        conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Offline banner
            if !network.isConnected {
                offlineBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if sortedMessages.isEmpty && !streaming.isStreaming {
                        emptyState
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(sortedMessages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }

                            if streaming.isStreaming {
                                if !streaming.streamingThinking.isEmpty || !streaming.streamingContent.isEmpty {
                                    streamingBubble
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
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                }
                .onChange(of: sortedMessages.count) { scrollToBottom(proxy: proxy) }
                .onChange(of: streaming.streamingContent) { scrollToBottom(proxy: proxy) }
            }

            inputBar
        }
        .background(Color.bgPrimary)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if !conversation.modelName.isEmpty {
                        Text(conversation.modelName)
                            .font(.app(11, weight: .medium))
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color.accentSoft)
                            )
                            .onTapGesture { showModelPicker = true }
                    }

                    Button { showModelPicker = true } label: {
                        Image(systemName: "cpu")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Button { showParameters = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView { model in
                conversation.modelName = model.name
                try? modelContext.save()
                showModelPicker = false
            }
        }
        .sheet(isPresented: $showParameters) {
            ParametersView(conversation: conversation)
        }
    }

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text("Offline")
                .font(.app(12, weight: .semibold))
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
                    .font(.system(size: 40, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(Color.textTertiary)
                Text("Pick a model to begin")
                    .font(.app(15))
                    .foregroundStyle(Color.textSecondary)
                Button {
                    showModelPicker = true
                } label: {
                    Text("Choose Model")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(LinearGradient.accentGradient))
                }
                .padding(.top, 4)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(Color.accent.opacity(0.4))
                Text("Send a message to begin")
                    .font(.app(15))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Streaming

    private var streamingRendered: AttributedString {
        (try? AttributedString(markdown: streaming.streamingContent, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(streaming.streamingContent)
    }

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
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                Text(streaming.isThinking ? "Thinking..." : "Thinking")
                                    .font(.app(12, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .rotationEffect(.degrees(showStreamingThinking ? 90 : 0))
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if showStreamingThinking {
                            Text(streaming.streamingThinking)
                                .font(.app(13))
                                .foregroundStyle(Color.textTertiary)
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
                    Text(streamingRendered)
                        .textSelection(.enabled)
                        .font(.app(15))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.assistantBubble)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: streaming.streamingThinking.isEmpty ? 20 : 0,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 20,
                                topTrailingRadius: streaming.streamingThinking.isEmpty ? 20 : 0,
                                style: .continuous
                            )
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: streaming.streamingThinking.isEmpty ? 20 : 0,
                                bottomLeadingRadius: 20,
                                bottomTrailingRadius: 20,
                                topTrailingRadius: streaming.streamingThinking.isEmpty ? 20 : 0,
                                style: .continuous
                            )
                            .stroke(Color.border, lineWidth: 0.5)
                        )
                }
            }
            Spacer(minLength: 48)
        }
    }

    private func errorBubble(_ message: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, design: .rounded))
                    Text(message)
                        .font(.app(13))
                }
                .foregroundStyle(Color.danger)

                // Retry button
                if let lastContent = streaming.lastSentContent, !streaming.isStreaming {
                    Button {
                        retry(content: lastContent)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Text("Retry")
                                .font(.app(12, weight: .semibold))
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
                TextField("Message", text: $input, axis: .vertical)
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
                        streaming.cancel(conversation: conversation, modelContext: modelContext)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Color.danger))
                    }
                } else {
                    Button(action: send) {
                        Image(systemName: canSend ? "arrow.up" : (network.isConnected ? "arrow.up" : "wifi.slash"))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
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

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        streaming.sendMessage(content: text, conversation: conversation, modelContext: modelContext)
    }

    private func retry(content: String) {
        streaming.error = nil

        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        streaming.sendMessage(content: content, conversation: conversation, modelContext: modelContext)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if streaming.isStreaming {
            if !streaming.streamingContent.isEmpty || !streaming.streamingThinking.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else {
                proxy.scrollTo("typing", anchor: .bottom)
            }
        } else if let last = sortedMessages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
