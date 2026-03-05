import Foundation
import SwiftData

@MainActor
class StreamingChatService: ObservableObject {
    @Published var streamingContent = ""
    @Published var streamingThinking = ""
    @Published var isStreaming = false
    @Published var isThinking = false
    @Published var error: String?

    private var streamTask: Task<Void, Never>?

    func sendMessage(
        content: String,
        conversation: Conversation,
        modelContext: ModelContext
    ) {
        // Create and persist user message
        let userMessage = Message(role: "user", content: content, conversation: conversation)
        modelContext.insert(userMessage)
        conversation.updatedAt = Date()

        // Auto-title from first user message
        if conversation.messages.count <= 1 && conversation.title == "New Chat" {
            let preview = String(content.prefix(40))
            conversation.title = content.count > 40 ? "\(preview)..." : preview
        }

        try? modelContext.save()

        // Build messages array for API
        var requestMessages: [ChatRequestMessage] = []

        if !conversation.systemPrompt.isEmpty {
            requestMessages.append(ChatRequestMessage(role: "system", content: conversation.systemPrompt))
        }

        let sorted = (conversation.messages).sorted { $0.createdAt < $1.createdAt }
        for msg in sorted {
            requestMessages.append(ChatRequestMessage(role: msg.role, content: msg.content))
        }

        let options = ChatOptions(
            temperature: conversation.temperature,
            top_p: conversation.topP,
            top_k: conversation.topK,
            num_predict: conversation.numPredict
        )

        let model = conversation.modelName

        // Start streaming
        isStreaming = true
        isThinking = false
        streamingContent = ""
        streamingThinking = ""
        error = nil

        streamTask = Task {
            do {
                let (bytes, _) = try await OllamaAPIClient.shared.streamChat(
                    model: model,
                    messages: requestMessages,
                    options: options
                )

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard !line.isEmpty else { continue }

                    guard let data = line.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
                        continue
                    }

                    if let thinking = chunk.message?.thinking, !thinking.isEmpty {
                        isThinking = true
                        streamingThinking += thinking
                    }

                    if let token = chunk.message?.content, !token.isEmpty {
                        if isThinking {
                            isThinking = false
                        }
                        streamingContent += token
                    }

                    if chunk.done {
                        break
                    }
                }

                // Persist the assistant message
                if !streamingContent.isEmpty || !streamingThinking.isEmpty {
                    let assistantMessage = Message(
                        role: "assistant",
                        content: streamingContent,
                        thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
                        conversation: conversation
                    )
                    modelContext.insert(assistantMessage)
                    conversation.updatedAt = Date()
                    try? modelContext.save()
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription

                    // Save partial response if we have one
                    if !streamingContent.isEmpty || !streamingThinking.isEmpty {
                        let partialMessage = Message(
                            role: "assistant",
                            content: streamingContent,
                            thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
                            conversation: conversation
                        )
                        modelContext.insert(partialMessage)
                        try? modelContext.save()
                    }
                }
            }

            streamingContent = ""
            streamingThinking = ""
            isStreaming = false
            isThinking = false
        }
    }

    func cancel(conversation: Conversation, modelContext: ModelContext) {
        streamTask?.cancel()

        // Save partial content if any
        if !streamingContent.isEmpty || !streamingThinking.isEmpty {
            let partialMessage = Message(
                role: "assistant",
                content: streamingContent.isEmpty ? "[stopped during thinking]" : streamingContent + "\n\n[stopped]",
                thinkingContent: streamingThinking.isEmpty ? nil : streamingThinking,
                conversation: conversation
            )
            modelContext.insert(partialMessage)
            try? modelContext.save()
        }

        streamingContent = ""
        streamingThinking = ""
        isStreaming = false
        isThinking = false
        streamTask = nil
    }
}
