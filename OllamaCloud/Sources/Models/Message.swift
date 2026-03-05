import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var role: String  // "user", "assistant", "system"
    var content: String
    var thinkingContent: String?
    var createdAt: Date
    var conversation: Conversation?

    init(role: String, content: String, thinkingContent: String? = nil, conversation: Conversation? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.createdAt = Date()
        self.conversation = conversation
    }
}
