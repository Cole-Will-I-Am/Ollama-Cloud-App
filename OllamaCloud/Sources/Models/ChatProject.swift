import Foundation
import SwiftData

/// A lightweight "Project" (context workspace), mirroring the manticthink website's
/// Projects: a name + custom instructions + attached context files. Its instructions
/// and files are compiled into a system message and injected on every send in the
/// project's chats. Distinct from `Project` (the code workspace that backs Codebases).
///
/// Chats are grouped into a project via `Conversation.projectID == ChatProject.id`.
@Model
final class ChatProject {
    var id: UUID
    var name: String
    var accountScopeKey: String
    var instructions: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProjectContextFile.project)
    var files: [ProjectContextFile]

    init(
        name: String = "New Project",
        accountScopeKey: String = "",
        instructions: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.accountScopeKey = accountScopeKey
        self.instructions = instructions
        self.createdAt = Date()
        self.updatedAt = Date()
        self.files = []
    }
}
