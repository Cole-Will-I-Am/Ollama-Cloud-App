import Foundation
import SwiftData

/// Built-in file operation tools for the Code workspace.
/// Models discover these through Ollama's tool calling schema when a project is active.
enum CodeToolkit {

    // MARK: - Public API

    static let toolNames: Set<String> = Set(tools.map(\.function.name))

    static func handles(_ toolName: String) -> Bool {
        toolNames.contains(toolName)
    }

    static func execute(
        toolName: String,
        arguments: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool) {
        switch toolName {
        case "create_file":       return createFile(arguments, project: project, modelContext: modelContext)
        case "write_file":        return writeFile(arguments, project: project, modelContext: modelContext)
        case "edit_file":         return editFile(arguments, project: project, modelContext: modelContext)
        case "read_file":         return readFile(arguments, project: project)
        case "delete_file":       return deleteFile(arguments, project: project, modelContext: modelContext)
        case "create_directory":  return createDirectory(arguments, project: project, modelContext: modelContext)
        case "list_files":        return listFiles(project: project)
        case "move_file":         return moveFile(arguments, project: project, modelContext: modelContext)
        default:                  return ("Unknown code tool: \(toolName)", true)
        }
    }

    // MARK: - Tool Definitions

    static let tools: [ChatTool] = [
        ChatTool(function: ChatToolFunction(
            name: "create_file",
            description: "Create a new file at the given path with the provided content. Parent directories are created automatically.",
            parameters: ChatToolParameters(
                required: ["path", "content"],
                properties: [
                    "path": ChatToolProperty(type: "string", description: "File path relative to project root, e.g. \"src/main.py\""),
                    "content": ChatToolProperty(type: "string", description: "The file content to write")
                ]
            )
        )),
        ChatTool(function: ChatToolFunction(
            name: "write_file",
            description: "Replace an existing file's entire content. Creates the file if it doesn't exist.",
            parameters: ChatToolParameters(
                required: ["path", "content"],
                properties: [
                    "path": ChatToolProperty(type: "string", description: "File path relative to project root"),
                    "content": ChatToolProperty(type: "string", description: "The new file content")
                ]
            )
        )),
        ChatTool(function: ChatToolFunction(
            name: "edit_file",
            description: "Search-and-replace within a file. Replaces the first occurrence of old_text with new_text.",
            parameters: ChatToolParameters(
                required: ["path", "old_text", "new_text"],
                properties: [
                    "path": ChatToolProperty(type: "string", description: "File path relative to project root"),
                    "old_text": ChatToolProperty(type: "string", description: "The exact text to find and replace"),
                    "new_text": ChatToolProperty(type: "string", description: "The replacement text")
                ]
            )
        )),
        ChatTool(function: ChatToolFunction(
            name: "read_file",
            description: "Read a file's content. Returns the full text of the file.",
            parameters: ChatToolParameters(
                required: ["path"],
                properties: [
                    "path": ChatToolProperty(type: "string", description: "File path relative to project root")
                ]
            )
        )),
        ChatTool(function: ChatToolFunction(
            name: "delete_file",
            description: "Delete a file or an empty directory.",
            parameters: ChatToolParameters(
                required: ["path"],
                properties: [
                    "path": ChatToolProperty(type: "string", description: "File path relative to project root")
                ]
            )
        )),
        ChatTool(function: ChatToolFunction(
            name: "create_directory",
            description: "Create a directory at the given path. Parent directories are created automatically.",
            parameters: ChatToolParameters(
                required: ["path"],
                properties: [
                    "path": ChatToolProperty(type: "string", description: "Directory path relative to project root, e.g. \"src/utils\"")
                ]
            )
        )),
        ChatTool(function: ChatToolFunction(
            name: "list_files",
            description: "List all files and directories in the project as a tree.",
            parameters: ChatToolParameters(properties: [:])
        )),
        ChatTool(function: ChatToolFunction(
            name: "move_file",
            description: "Move or rename a file or directory.",
            parameters: ChatToolParameters(
                required: ["old_path", "new_path"],
                properties: [
                    "old_path": ChatToolProperty(type: "string", description: "Current file path"),
                    "new_path": ChatToolProperty(type: "string", description: "New file path")
                ]
            )
        ))
    ]

    // MARK: - Tool Implementations

    private static func normalizePath(_ raw: String) -> String {
        var normalized: [Substring] = []
        for component in raw.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !normalized.isEmpty {
                    normalized.removeLast()
                }
            default:
                normalized.append(component)
            }
        }
        return normalized.map(String.init).joined(separator: "/")
    }

    private static func findFile(path: String, in project: Project) -> ProjectFile? {
        let normalized = normalizePath(path)
        return project.files.first { $0.path == normalized }
    }

    private static func ensureParentDirectories(for path: String, project: Project, modelContext: ModelContext) {
        let components = path.split(separator: "/").dropLast()
        var accumulated = ""
        for component in components {
            if !accumulated.isEmpty { accumulated += "/" }
            accumulated += String(component)
            if let existing = findFile(path: accumulated, in: project) {
                // A regular file already occupies a parent slot; don't bury a
                // child under it (the child would be hidden/orphaned in the tree).
                if !existing.isDirectory { return }
            } else {
                let dir = ProjectFile(path: accumulated, content: "", isDirectory: true, project: project)
                modelContext.insert(dir)
            }
        }
    }

    private static func createFile(
        _ args: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool) {
        guard let pathVal = args["path"]?.stringValue else {
            return ("Missing required parameter: path", true)
        }
        let path = normalizePath(pathVal)
        guard !path.isEmpty else { return ("Invalid path", true) }

        let content = args["content"]?.stringValue ?? ""

        if findFile(path: path, in: project) != nil {
            return ("File already exists: \(path). Use write_file to overwrite.", true)
        }

        ensureParentDirectories(for: path, project: project, modelContext: modelContext)
        let file = ProjectFile(path: path, content: content, project: project)
        modelContext.insert(file)
        project.updatedAt = Date()

        return ("Created \(path) (\(content.count) bytes)", false)
    }

    private static func writeFile(
        _ args: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool) {
        guard let pathVal = args["path"]?.stringValue else {
            return ("Missing required parameter: path", true)
        }
        let path = normalizePath(pathVal)
        guard !path.isEmpty else { return ("Invalid path", true) }

        let content = args["content"]?.stringValue ?? ""

        if let existing = findFile(path: path, in: project) {
            if existing.isDirectory {
                return ("Cannot write to a directory: \(path)", true)
            }
            existing.content = content
            existing.updatedAt = Date()
        } else {
            ensureParentDirectories(for: path, project: project, modelContext: modelContext)
            let file = ProjectFile(path: path, content: content, project: project)
            modelContext.insert(file)
        }
        project.updatedAt = Date()

        return ("Wrote \(path) (\(content.count) bytes)", false)
    }

    private static func editFile(
        _ args: [String: JSONValue],
        project: Project,
        modelContext _: ModelContext
    ) -> (content: String, isError: Bool) {
        guard let pathVal = args["path"]?.stringValue else {
            return ("Missing required parameter: path", true)
        }
        let path = normalizePath(pathVal)

        guard let oldText = args["old_text"]?.stringValue else {
            return ("Missing required parameter: old_text", true)
        }
        guard let newText = args["new_text"]?.stringValue else {
            return ("Missing required parameter: new_text", true)
        }

        guard let file = findFile(path: path, in: project) else {
            return ("File not found: \(path)", true)
        }
        guard !file.isDirectory else {
            return ("Cannot edit a directory: \(path)", true)
        }

        guard let range = file.content.range(of: oldText) else {
            return ("old_text not found in \(path)", true)
        }

        file.content.replaceSubrange(range, with: newText)
        file.updatedAt = Date()
        project.updatedAt = Date()

        return ("Edited \(path): replaced \(oldText.count) chars with \(newText.count) chars", false)
    }

    private static func readFile(
        _ args: [String: JSONValue],
        project: Project
    ) -> (content: String, isError: Bool) {
        guard let pathVal = args["path"]?.stringValue else {
            return ("Missing required parameter: path", true)
        }
        let path = normalizePath(pathVal)

        guard let file = findFile(path: path, in: project) else {
            return ("File not found: \(path)", true)
        }
        if file.isDirectory {
            let children = project.files
                .filter { $0.path.hasPrefix(path + "/") && !$0.path.dropFirst(path.count + 1).contains("/") }
                .map { ($0.isDirectory ? "\($0.path)/" : $0.path) }
                .sorted()
            return ("Directory: \(path)/\n" + children.joined(separator: "\n"), false)
        }
        return (file.content, false)
    }

    private static func deleteFile(
        _ args: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool) {
        guard let pathVal = args["path"]?.stringValue else {
            return ("Missing required parameter: path", true)
        }
        let path = normalizePath(pathVal)

        guard let file = findFile(path: path, in: project) else {
            return ("File not found: \(path)", true)
        }

        if file.isDirectory {
            let children = project.files.filter { $0.path.hasPrefix(path + "/") }
            if !children.isEmpty {
                return ("Directory not empty: \(path) (\(children.count) items). Delete contents first.", true)
            }
        }

        modelContext.delete(file)
        project.updatedAt = Date()
        return ("Deleted \(path)", false)
    }

    private static func createDirectory(
        _ args: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool) {
        guard let pathVal = args["path"]?.stringValue else {
            return ("Missing required parameter: path", true)
        }
        let path = normalizePath(pathVal)
        guard !path.isEmpty else { return ("Invalid path", true) }

        if findFile(path: path, in: project) != nil {
            return ("Path already exists: \(path)", true)
        }

        ensureParentDirectories(for: path, project: project, modelContext: modelContext)
        let dir = ProjectFile(path: path, content: "", isDirectory: true, project: project)
        modelContext.insert(dir)
        project.updatedAt = Date()

        return ("Created directory \(path)/", false)
    }

    private static func listFiles(project: Project) -> (content: String, isError: Bool) {
        let files = project.files.sorted { $0.path < $1.path }
        guard !files.isEmpty else {
            return ("(empty project)", false)
        }
        return (buildTreeString(from: files), false)
    }

    private static func moveFile(
        _ args: [String: JSONValue],
        project: Project,
        modelContext: ModelContext
    ) -> (content: String, isError: Bool) {
        guard let oldPathVal = args["old_path"]?.stringValue else {
            return ("Missing required parameter: old_path", true)
        }
        guard let newPathVal = args["new_path"]?.stringValue else {
            return ("Missing required parameter: new_path", true)
        }
        let oldPath = normalizePath(oldPathVal)
        let newPath = normalizePath(newPathVal)
        guard !oldPath.isEmpty else { return ("Invalid old_path", true) }
        guard !newPath.isEmpty else { return ("Invalid new_path", true) }

        guard let file = findFile(path: oldPath, in: project) else {
            return ("File not found: \(oldPath)", true)
        }
        if findFile(path: newPath, in: project) != nil {
            return ("Destination already exists: \(newPath)", true)
        }

        if file.isDirectory {
            let prefix = oldPath + "/"

            // Refuse to move a directory into its own subtree (would orphan it).
            if newPath == oldPath || (newPath + "/").hasPrefix(prefix) {
                return ("Cannot move a directory into itself: \(oldPath) → \(newPath)", true)
            }

            // Refuse if any rewritten child path would collide with an existing
            // file outside the moved subtree — otherwise two ProjectFiles share a
            // path and one becomes unreachable (silent data loss).
            let newPrefix = newPath + "/"
            for child in project.files where child.path.hasPrefix(prefix) {
                let candidate = newPrefix + child.path.dropFirst(prefix.count)
                let collides = project.files.contains {
                    $0.id != child.id && !$0.path.hasPrefix(prefix) && $0.path == candidate
                }
                if collides {
                    return ("Cannot move: destination already contains \(candidate)", true)
                }
            }

            for child in project.files where child.path.hasPrefix(prefix) {
                child.path = newPath + "/" + child.path.dropFirst(prefix.count)
                child.updatedAt = Date()
            }
        }

        ensureParentDirectories(for: newPath, project: project, modelContext: modelContext)
        file.path = newPath
        file.updatedAt = Date()
        project.updatedAt = Date()

        return ("Moved \(oldPath) → \(newPath)", false)
    }

    // MARK: - Tree String Builder

    private static func buildTreeString(from files: [ProjectFile]) -> String {
        final class TreeNode {
            let name: String
            let isDirectory: Bool
            var children: [String: TreeNode] = [:]

            init(name: String, isDirectory: Bool) {
                self.name = name
                self.isDirectory = isDirectory
            }
        }

        // Use a sentinel root node; class semantics allow mutation through references
        let root = TreeNode(name: "", isDirectory: true)

        for file in files {
            let parts = file.path.split(separator: "/").map(String.init)
            var current = root
            for (i, part) in parts.enumerated() {
                let isLast = i == parts.count - 1
                if current.children[part] == nil {
                    current.children[part] = TreeNode(
                        name: part,
                        isDirectory: isLast ? file.isDirectory : true
                    )
                }
                if !isLast {
                    current = current.children[part]!
                }
            }
        }

        func render(_ nodes: [String: TreeNode], prefix: String) -> String {
            let sorted = nodes.sorted { lhs, rhs in
                if lhs.value.isDirectory != rhs.value.isDirectory {
                    return lhs.value.isDirectory
                }
                return lhs.key < rhs.key
            }

            var lines: [String] = []
            for (i, (_, node)) in sorted.enumerated() {
                let isLast = i == sorted.count - 1
                let connector = isLast ? "└── " : "├── "
                let suffix = node.isDirectory ? "/" : ""
                lines.append(prefix + connector + node.name + suffix)

                if !node.children.isEmpty {
                    let childPrefix = prefix + (isLast ? "    " : "│   ")
                    lines.append(render(node.children, prefix: childPrefix))
                }
            }
            return lines.joined(separator: "\n")
        }

        return render(root.children, prefix: "")
    }
}
