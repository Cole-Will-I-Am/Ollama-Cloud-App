import Foundation
import SwiftData

@MainActor
class StreamingChatService: ObservableObject {
    @Published var streamingContent = ""
    @Published var isStreaming = false
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
        streamingContent = ""
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

                    if let token = chunk.message?.content {
                        streamingContent += token
                    }

                    if chunk.done {
                        break
                    }
                }

                // Persist the assistant message
                if !streamingContent.isEmpty {
                    let assistantMessage = Message(
                        role: "assistant",
                        content: streamingContent,
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
                    if !streamingContent.isEmpty {
                        let partialMessage = Message(
                            role: "assistant",
                            content: streamingContent,
                            conversation: conversation
                        )
                        modelContext.insert(partialMessage)
                        try? modelContext.save()
                    }
                }
            }

            streamingContent = ""
            isStreaming = false
        }
    }

    func cancel(conversation: Conversation, modelContext: ModelContext) {
        streamTask?.cancel()

        // Save partial content if any
        if !streamingContent.isEmpty {
            let partialMessage = Message(
                role: "assistant",
                content: streamingContent + "\n\n[stopped]",
                conversation: conversation
            )
            modelContext.insert(partialMessage)
            try? modelContext.save()
        }

        streamingContent = ""
        isStreaming = false
        streamTask = nil
    }
}
