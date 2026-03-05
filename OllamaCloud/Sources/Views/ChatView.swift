import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
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
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    if sortedMessages.isEmpty && !streaming.isStreaming {
                        emptyState
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(sortedMessages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }

                            // Streaming
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
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .onChange(of: sortedMessages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streaming.streamingContent) {
                    scrollToBottom(proxy: proxy)
                }
            }

            // Input bar
            inputBar
        }
        .background(Color.bgPrimary)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    // Model badge
                    if !conversation.modelName.isEmpty {
                        Text(conversation.modelName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.accent.opacity(0.1))
                                    .overlay(
                                        Capsule().stroke(Color.accent.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                            .onTapGesture { showModelPicker = true }
                    }

                    Button {
                        showModelPicker = true
                    } label: {
                        Image(systemName: "cpu")
                            .font(.body.weight(.light))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Button {
                        showParameters = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.light))
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if conversation.modelName.isEmpty {
                Image(systemName: "cpu")
                    .font(.system(size: 44, weight: .ultraLight))
                    .foregroundStyle(Color.textTertiary)
                Text("Select a model")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Button {
                    showModelPicker = true
                } label: {
                    Text("Choose Model")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(LinearGradient.accentGradient)
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Color.accent.opacity(0.5))
                Text("Start a conversation")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Streaming Bubble

    private var streamingRendered: AttributedString {
        (try? AttributedString(markdown: streaming.streamingContent, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(streaming.streamingContent)
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Thinking
                if !streaming.streamingThinking.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showStreamingThinking.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "brain")
                                    .font(.caption2)
                                Text(streaming.isThinking ? "Thinking..." : "Thinking")
                                    .font(.caption2.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .rotationEffect(.degrees(showStreamingThinking ? 90 : 0))
                            }
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if showStreamingThinking {
                            Text(streaming.streamingThinking)
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                    .background(Color.white.opacity(0.02))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: streaming.streamingContent.isEmpty ? 16 : 0,
                            bottomTrailingRadius: streaming.streamingContent.isEmpty ? 16 : 0,
                            topTrailingRadius: 16
                        )
                    )
                    .overlay(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: streaming.streamingContent.isEmpty ? 16 : 0,
                            bottomTrailingRadius: streaming.streamingContent.isEmpty ? 16 : 0,
                            topTrailingRadius: 16
                        )
                        .stroke(Color.border, lineWidth: 0.5)
                    )
                }

                // Content
                if !streaming.streamingContent.isEmpty {
                    Text(streamingRendered)
                        .textSelection(.enabled)
                        .padding(12)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .background(Color.assistantBubble)
                        .clipShape(
                            .rect(
                                topLeadingRadius: streaming.streamingThinking.isEmpty ? 16 : 0,
                                bottomLeadingRadius: 16,
                                bottomTrailingRadius: 16,
                                topTrailingRadius: streaming.streamingThinking.isEmpty ? 16 : 0
                            )
                        )
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: streaming.streamingThinking.isEmpty ? 16 : 0,
                                bottomLeadingRadius: 16,
                                bottomTrailingRadius: 16,
                                topTrailingRadius: streaming.streamingThinking.isEmpty ? 16 : 0
                            )
                            .stroke(Color.border, lineWidth: 0.5)
                        )
                }
            }
            Spacer(minLength: 60)
        }
    }

    private func errorBubble(_ message: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                Text(message)
                    .font(.caption)
            }
            .foregroundStyle(Color.danger)
            .padding(12)
            .background(Color.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.danger.opacity(0.15), lineWidth: 0.5)
            )
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 0.5)

            HStack(spacing: 12) {
                TextField("Message...", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.bgSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.borderLight, lineWidth: 0.5)
                            )
                    )
                    .onSubmit { send() }

                if streaming.isStreaming {
                    Button {
                        streaming.cancel(conversation: conversation, modelContext: modelContext)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.danger)
                    }
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(canSend ? Color.accent : Color.textTertiary.opacity(0.4))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bgPrimary)
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !streaming.isStreaming
        && !conversation.modelName.isEmpty
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !conversation.modelName.isEmpty else { return }
        input = ""

        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif

        streaming.sendMessage(content: text, conversation: conversation, modelContext: modelContext)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if streaming.isStreaming {
            if !streaming.streamingContent.isEmpty || !streaming.streamingThinking.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else {
                proxy.scrollTo("typing", anchor: .bottom)
            }
        } else if let last = sortedMessages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
