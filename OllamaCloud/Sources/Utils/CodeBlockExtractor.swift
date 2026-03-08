import Foundation

struct ExtractedCodeBlock: Identifiable {
    let id: String              // "{messageID}-{index}"
    let language: String        // from fence info, e.g. "python"
    let code: String
    let sourceMessageID: UUID
    let index: Int
}

enum CodeBlockExtractor {
    /// Returns prose with code fences replaced by `[code: language]` placeholders,
    /// plus an array of extracted blocks.
    static func extract(from content: String, messageID: UUID) -> (prose: String, codeBlocks: [ExtractedCodeBlock]) {
        let lines = content.components(separatedBy: "\n")
        var prose = ""
        var blocks: [ExtractedCodeBlock] = []
        var inFence = false
        var fenceLanguage = ""
        var fenceLines: [String] = []

        for line in lines {
            if inFence {
                if line.hasPrefix("```") {
                    // Closing fence — emit block
                    let code = fenceLines.joined(separator: "\n")
                    let idx = blocks.count
                    let block = ExtractedCodeBlock(
                        id: "\(messageID.uuidString)-\(idx)",
                        language: fenceLanguage,
                        code: code,
                        sourceMessageID: messageID,
                        index: idx
                    )
                    blocks.append(block)
                    let label = fenceLanguage.isEmpty ? "code" : fenceLanguage
                    prose += "[code: \(label)]"
                    inFence = false
                    fenceLanguage = ""
                    fenceLines = []
                } else {
                    fenceLines.append(line)
                }
            } else {
                if line.hasPrefix("```") {
                    // Opening fence — capture language
                    let info = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    fenceLanguage = info.split(separator: " ").first.map(String.init) ?? ""
                    inFence = true
                    fenceLines = []
                } else {
                    if !prose.isEmpty { prose += "\n" }
                    prose += line
                }
            }
        }

        // Handle unclosed fence (partial streaming)
        if inFence, !fenceLines.isEmpty {
            let code = fenceLines.joined(separator: "\n")
            let idx = blocks.count
            let block = ExtractedCodeBlock(
                id: "\(messageID.uuidString)-\(idx)",
                language: fenceLanguage,
                code: code,
                sourceMessageID: messageID,
                index: idx
            )
            blocks.append(block)
            let label = fenceLanguage.isEmpty ? "code" : fenceLanguage
            prose += "[code: \(label)]"
        }

        return (prose, blocks)
    }

    /// Convenience — returns just the prose portion with code fences stripped.
    static func stripCodeBlocks(from content: String) -> String {
        extract(from: content, messageID: UUID()).prose
    }
}
