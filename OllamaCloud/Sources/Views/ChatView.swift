import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation
    @StateObject private var streaming = StreamingChatService()
    @State private var input = ""
    @State private var showModelPicker = false
    @State private var showParameters = false

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
                        LazyVStack(spacing: 12) {
                            ForEach(sortedMessages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }

                            // Streaming content
                            if streaming.isStreaming {
                                if !streaming.streamingThinking.isEmpty || !streaming.streamingContent.isEmpty {
                                    streamingBubble
                                        .id("streaming")
                                } else {
                                    TypingIndicator()
                                        .id("typing")
                                }
                            }

                            // Error
                            if let error = streaming.error {
                                errorBubble(error)
                            }
                        }
                        .padding()
                    }
                }
                .onChange(of: sortedMessages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: streaming.streamingContent) {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()
                .background(Color.border)

            // Input bar
            inputBar
        }
        .background(Color.bgPrimary)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showModelPicker = true
                    } label: {
                        Image(systemName: "cpu")
                            .foregroundStyle(Color.textSecondary)
                    }

                    Button {
                        showParameters = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
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

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if conversation.modelName.isEmpty {
                Image(systemName: "cpu")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.textSecondary)
                Text("Select a model to start chatting")
                    .foregroundStyle(Color.textSecondary)
                Button("Choose Model") {
                    showModelPicker = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.textSecondary)
                Text("Send a message to start chatting with **\(conversation.modelName)**")
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var streamingRendered: AttributedString {
        (try? AttributedString(markdown: streaming.streamingContent, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(streaming.streamingContent)
    }

    @State private var showStreamingThinking = true

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Thinking section (while thinking or if thinking completed)
                if !streaming.streamingThinking.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showStreamingThinking.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "brain")
                                    .font(.caption)
                                if streaming.isThinking {
                                    Text("Thinking...")
                                        .font(.caption.weight(.medium))
                                } else {
                                    Text("Thinking")
                                        .font(.caption.weight(.medium))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .rotationEffect(.degrees(showStreamingThinking ? 90 : 0))
                            }
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if showStreamingThinking {
                            Text(streaming.streamingThinking)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                    .background(Color.assistantBubble.opacity(0.7))
                    .clipShape(
                        .rect(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: streaming.streamingContent.isEmpty ? 16 : 0,
                            bottomTrailingRadius: streaming.streamingContent.isEmpty ? 16 : 0,
                            topTrailingRadius: 16
                        )
                    )
                }

                // Response content
                if !streaming.streamingContent.isEmpty {
                    Text(streamingRendered)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color.assistantBubble)
                        .foregroundStyle(Color.textPrimary)
                        .clipShape(
                            .rect(
                                topLeadingRadius: streaming.streamingThinking.isEmpty ? 16 : 0,
                                bottomLeadingRadius: 16,
                                bottomTrailingRadius: 16,
                                topTrailingRadius: streaming.streamingThinking.isEmpty ? 16 : 0
                            )
                        )
                        .font(.body)
                }
            }
            Spacer(minLength: 60)
        }
    }

    private func errorBubble(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Color.danger)
                .padding(12)
                .background(Color.danger.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer()
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message...", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.border, lineWidth: 1)
                )
                .onSubmit { send() }

            if streaming.isStreaming {
                Button {
                    streaming.cancel(conversation: conversation, modelContext: modelContext)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.danger)
                }
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? Color.accent : Color.border)
                }
                .disabled(!canSend)
            }
        }
        .padding()
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
            if !streaming.streamingContent.isEmpty {
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
