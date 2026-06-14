import Foundation

/// Compiles a lightweight `ChatProject` (name + instructions + context files)
/// into a single system message, injected on every send in the project's chats.
/// Direct port of the manticthink website's `compileProjectContext`.
enum ProjectContextCompiler {
    static func compile(_ project: ChatProject) -> String {
        var parts: [String] = []

        let head = "## Project: \(project.name)"
        let trimmedInstructions = project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(trimmedInstructions.isEmpty ? head : "\(head)\n\(trimmedInstructions)")

        for file in project.files.sorted(by: { $0.createdAt < $1.createdAt }) {
            parts.append("### Project file: \(file.name)\n```\n\(file.content)\n```")
        }

        parts.append("Use the project context above when relevant to the conversation.")
        return parts.joined(separator: "\n\n")
    }
}
