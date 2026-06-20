import SwiftUI
import MarkdownUI

/// One slice of an assistant message: ordinary Markdown, or a fenced ```document
/// block that should render as a downloadable document card.
enum DocumentSegment {
    case markdown(String)
    case document(title: String, markdown: String)
}

/// Splits an assistant message into Markdown / document segments. A ```document
/// (or ```doc) fenced block becomes a `.document`; everything else stays Markdown.
/// An unterminated block (still streaming) is left as Markdown until it closes.
enum DocumentParser {
    static func segments(from content: String) -> [DocumentSegment] {
        let lines = content.components(separatedBy: "\n")
        var segments: [DocumentSegment] = []
        var buffer: [String] = []

        func flush() {
            if !buffer.isEmpty {
                segments.append(.markdown(buffer.joined(separator: "\n")))
                buffer.removeAll()
            }
        }

        var i = 0
        while i < lines.count {
            let fence = lines[i].trimmingCharacters(in: .whitespaces).lowercased()
            if fence == "```document" || fence == "```doc" {
                var j = i + 1
                var bodyLines: [String] = []
                var closed = false
                while j < lines.count {
                    if lines[j].trimmingCharacters(in: .whitespaces) == "```" { closed = true; break }
                    bodyLines.append(lines[j]); j += 1
                }
                if closed {
                    flush()
                    let body = bodyLines.joined(separator: "\n")
                    segments.append(.document(title: title(for: body), markdown: body))
                    i = j + 1
                    continue
                }
                // No closing fence yet — fall through and treat as ordinary text.
            }
            buffer.append(lines[i])
            i += 1
        }
        flush()
        return segments.isEmpty ? [.markdown(content)] : segments
    }

    /// First `# ` heading, else the first non-empty line, else "Document".
    static func title(for markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") {
                return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return String(line.prefix(48)) }
        }
        return "Document"
    }
}

/// Renders an assistant message body. With no document blocks it is identical to
/// a plain `Markdown` view; document blocks render as cards with an Export button.
struct AssistantMessageBody: View {
    let content: String
    var onExportPDF: ((String, String) -> Void)? = nil

    private var segments: [DocumentSegment] { DocumentParser.segments(from: content) }

    var body: some View {
        if segments.count == 1, case .markdown(let md) = segments[0] {
            Markdown(md).markdownTheme(.seerAssistant)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    segmentView(seg)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func segmentView(_ seg: DocumentSegment) -> some View {
        switch seg {
        case .markdown(let md):
            if !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Markdown(md).markdownTheme(.seerAssistant)
            }
        case .document(let title, let md):
            DocumentCardView(title: title, markdown: md, onExportPDF: onExportPDF)
        }
    }
}

/// A generated document: title bar + an Export PDF button + the rendered body.
struct DocumentCardView: View {
    let title: String
    let markdown: String
    var onExportPDF: ((String, String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .ultraLight))
                Text(title)
                    .font(.appLabel(11))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    onExportPDF?(markdown, title)
                    Haptic.selection()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 11, weight: .regular))
                        Text("Export PDF").font(.appLabel(11))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .macPointingCursor()
                #endif
            }
            .foregroundStyle(Color.textSecondary)

            Markdown(markdown).markdownTheme(.seerAssistant)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.border, lineWidth: 0.5)
        )
    }
}
