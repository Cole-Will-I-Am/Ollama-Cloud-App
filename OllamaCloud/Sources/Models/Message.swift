import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var role: String  // "user", "assistant", "system", "tool_call", "tool"
    var content: String
    var thinkingContent: String?
    var attachmentRequestContent: String?
    var imageBase64sJSON: String?
    var outputTokenCount: Int?
    var toolCallsJSON: String?   // Serialized [{name, arguments}] for role == "tool_call"
    var toolName: String?        // Tool name for role == "tool" result messages
    var toolCallID: String?      // Provider tool-call identifier for role == "tool"
    var parentID: UUID?           // Parent message ID for DAG branching (nil = root or legacy)
    var createdAt: Date
    var conversation: Conversation?

    init(
        role: String,
        content: String,
        thinkingContent: String? = nil,
        attachmentRequestContent: String? = nil,
        imageBase64sJSON: String? = nil,
        outputTokenCount: Int? = nil,
        toolCallsJSON: String? = nil,
        toolName: String? = nil,
        toolCallID: String? = nil,
        parentID: UUID? = nil,
        conversation: Conversation? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.attachmentRequestContent = attachmentRequestContent
        self.imageBase64sJSON = imageBase64sJSON
        self.outputTokenCount = outputTokenCount
        self.toolCallsJSON = toolCallsJSON
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.parentID = parentID
        self.createdAt = Date()
        self.conversation = conversation
    }
}
