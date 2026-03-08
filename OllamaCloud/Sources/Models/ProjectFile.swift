import Foundation
import SwiftData

@Model
final class ProjectFile {
    var id: UUID
    var path: String
    var content: String
    var isDirectory: Bool
    var createdAt: Date
    var updatedAt: Date
    var project: Project?

    init(
        path: String,
        content: String = "",
        isDirectory: Bool = false,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.path = path
        self.content = content
        self.isDirectory = isDirectory
        self.createdAt = Date()
        self.updatedAt = Date()
        self.project = project
    }
}
