import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var accountScopeKey: String
    var conversationID: UUID
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProjectFile.project)
    var files: [ProjectFile]

    init(
        name: String = "New Project",
        accountScopeKey: String = "",
        conversationID: UUID = UUID()
    ) {
        self.id = UUID()
        self.name = name
        self.accountScopeKey = accountScopeKey
        self.conversationID = conversationID
        self.createdAt = Date()
        self.updatedAt = Date()
        self.files = []
    }
}
