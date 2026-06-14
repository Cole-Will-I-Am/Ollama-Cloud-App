import Foundation

/// Prompt/context builders for the Codebases agentic workspace (Builder + Reviewer).
/// Direct ports of the manticthink website's cbBuilderPersona / cbReviewerPersona /
/// cbReviewerUserPrompt / cbReviewerApproves / compileCodebaseContext.
enum CodebasePrompts {

    private static func fmtBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1_048_576 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.2f MB", Double(n) / 1_048_576)
    }

    private static func textFiles(_ project: Project) -> [ProjectFile] {
        project.files.filter { !$0.isDirectory }.sorted { $0.path < $1.path }
    }

    /// System message describing the codebase to the models — full file list
    /// always, bodies only up to a budget so we never blow the context window.
    static func compileCodebaseContext(_ project: Project, activePath: String? = nil) -> String {
        var parts: [String] = ["## Codebase: \(project.name.isEmpty ? "Untitled" : project.name)"]

        let files = textFiles(project)
        let listing = files.isEmpty
            ? "(empty — no files yet)"
            : files.map { "- \($0.path) (\(fmtBytes($0.content.utf8.count)))" }.joined(separator: "\n")
        parts.append("### Files\n\(listing)")

        var budget = 40 * 1024
        let ordered = files.sorted { a, b in
            if a.path == activePath { return true }
            if b.path == activePath { return false }
            return a.updatedAt > b.updatedAt
        }
        var bodies: [String] = []
        for f in ordered {
            let sz = f.content.utf8.count
            if sz > budget { continue }
            bodies.append("#### \(f.path)\n```\n\(f.content)\n```")
            budget -= sz
        }
        if !bodies.isEmpty {
            parts.append("### Current file contents\n" + bodies.joined(separator: "\n\n"))
        }
        parts.append("Use read_file to inspect any file not shown in full above. Make changes ONLY through the file tools.")
        return parts.joined(separator: "\n\n")
    }

    static func builderPersona(_ project: Project) -> String {
        let name = project.name.isEmpty ? "project" : project.name
        return [
            "You are the Builder, a senior software engineer constructing a multi-file codebase named \"\(name)\".",
            "You make ALL file changes through the provided tools: write_file, create_file, read_file, list_files, delete_file, move_file, edit_file.",
            "Always read_file before editing an existing file unless you are creating it. Write COMPLETE, runnable file contents — never partial diffs or \"// rest unchanged\".",
            "Keep files focused and idiomatic; prefer small, composable files. Do not paste whole file bodies into the chat — they live in the file tree.",
            "When a Reviewer has raised concerns, address them directly in your next changes.",
            "After your tool calls, end with a 2–4 line plain-text summary of what you changed and why.",
        ].joined(separator: "\n")
    }

    static func reviewerPersona() -> String {
        [
            "You are the Reviewer, a senior engineer doing a focused code review of the Builder's latest changes. You CANNOT edit files.",
            "You are shown the Builder's summary and the files it changed this round.",
            "Flag correctness bugs, security issues, broken imports/paths, and missing pieces first; then maintainability.",
            "Be concrete and concise (under 180 words). Describe the fix — do not rewrite whole files.",
            "If the changes are sound, say so plainly (e.g. \"Looks good — no blocking issues\") so the Builder can stop.",
        ].joined(separator: "\n")
    }

    static func reviewerUserPrompt(_ project: Project, builderSummary: String, changedPaths: [String]) -> String {
        let byPath = Dictionary(uniqueKeysWithValues: textFiles(project).map { ($0.path, $0) })
        var fileBlocks: [String] = []
        for path in changedPaths {
            guard let f = byPath[path] else { continue }
            var body = f.content
            if body.utf8.count > 20 * 1024 {
                body = String(body.prefix(20 * 1024)) + "\n…[truncated]"
            }
            fileBlocks.append("#### \(path)\n```\n\(body)\n```")
        }
        let changedSection = fileBlocks.isEmpty
            ? "(no file changes were detected this round)"
            : fileBlocks.joined(separator: "\n\n")
        let summary = builderSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Codebase: \(project.name.isEmpty ? "Untitled" : project.name)",
            "Builder's summary of this round:\n\(summary.isEmpty ? "(no summary provided)" : summary)",
            "Files changed this round:\n\(changedSection)",
            "Review these changes. If they're sound, say so plainly so the Builder can stop.",
        ].joined(separator: "\n\n")
    }

    /// True when the reviewer signalled the changes are good enough to stop.
    static func reviewerApproves(_ critique: String) -> Bool {
        let lowered = critique.lowercased()
        let markers = ["looks good", "lgtm", "no issues", "no blocking", "no concerns", "ship it", "approved"]
        return markers.contains { lowered.contains($0) }
    }
}
