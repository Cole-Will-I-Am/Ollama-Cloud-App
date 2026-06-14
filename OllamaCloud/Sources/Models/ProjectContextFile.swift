import Foundation
import SwiftData

/// A context file attached to a lightweight `ChatProject`. The `content` is plain
/// text that gets compiled into the project's injected system context (see
/// `ProjectContextCompiler`). Distinct from `ProjectFile`, which is a real file in
/// the Codebases code workspace.
@Model
final class ProjectContextFile {
    var id: UUID
    var name: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var project: ChatProject?

    init(
        name: String,
        content: String = "",
        project: ChatProject? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.createdAt = Date()
        self.updatedAt = Date()
        self.project = project
    }

    /// Byte size of the file content (UTF-8), used for the editor's size readout.
    var byteCount: Int { content.utf8.count }
}
