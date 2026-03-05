import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var role: String  // "user", "assistant", "system"
    var content: String
    var thinkingContent: String?
    var attachmentRequestContent: String?
    var imageBase64sJSON: String?
    var outputTokenCount: Int?
    var createdAt: Date
    var conversation: Conversation?

    init(
        role: String,
        content: String,
        thinkingContent: String? = nil,
        attachmentRequestContent: String? = nil,
        imageBase64sJSON: String? = nil,
        outputTokenCount: Int? = nil,
        conversation: Conversation? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.attachmentRequestContent = attachmentRequestContent
        self.imageBase64sJSON = imageBase64sJSON
        self.outputTokenCount = outputTokenCount
        self.createdAt = Date()
        self.conversation = conversation
    }
}
