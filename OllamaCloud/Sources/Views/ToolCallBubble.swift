import SwiftUI

// MARK: - Tool Call Bubble

struct ToolCallBubble: View {
    let toolCallsJSON: String?
    @State private var isExpanded = false

    private var toolCalls: [[String: Any]] {
        guard let json = toolCallsJSON,
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(toolCalls.enumerated()), id: \.offset) { _, call in
                    let name = call["name"] as? String ?? "unknown"
                    let args = call["arguments"] as? [String: Any]

                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 10, weight: .medium))
                                Text(name)
                                    .font(.appMono(11, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .medium))
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                            .foregroundStyle(Color.accent)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .macPointingCursor()
                        #endif

                        if isExpanded, let args {
                            let formatted = formatArguments(args)
                            Text(formatted)
                                .font(.appMono(10, weight: .regular))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(12)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.accent.opacity(0.15), lineWidth: 0.5)
                    )
            )
            .frame(maxWidth: 500, alignment: .leading)

            Spacer(minLength: 48)
        }
    }

    private func formatArguments(_ args: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: args, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{...}"
        }
        return text
    }
}

// MARK: - Tool Result Bubble

struct ToolResultBubble: View {
    let toolName: String?
    let content: String
    @State private var isExpanded: Bool

    init(toolName: String?, content: String) {
        self.toolName = toolName
        self.content = content
        // Auto-expand only trusted built-in visual HTML results.
        let isVisualHTML = Self.detectHTML(content) && (toolName.map(VisualsToolkit.handles) ?? false)
        self._isExpanded = State(initialValue: isVisualHTML)
    }

    private var isError: Bool {
        content.hasPrefix("Tool error:") || content.hasPrefix("Unknown tool:") || content.contains("timed out")
    }

    private var isHTMLContent: Bool {
        Self.detectHTML(content)
    }

    private var isTrustedVisualHTML: Bool {
        isHTMLContent && (toolName.map(VisualsToolkit.handles) ?? false)
    }

    private static func detectHTML(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<!DOCTYPE html>") || trimmed.hasPrefix("<html")
    }

    private var displayName: String {
        toolName ?? "tool"
    }

    private var htmlHeight: CGFloat {
        guard let name = toolName else { return 300 }
        switch name {
        case "render_table", "render_comparison_table": return 250
        case "render_metrics_grid": return 200
        case "render_dashboard": return 450
        case "render_timeline", "render_flowchart", "render_tree": return 280
        default: return 300
        }
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isTrustedVisualHTML ? "chart.bar.xaxis" : (isError ? "xmark.circle" : "checkmark.circle"))
                            .font(.system(size: 10, weight: .medium))
                        Text(displayName)
                            .font(.appMono(11, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .medium))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .foregroundStyle(isError ? Color.danger : (isTrustedVisualHTML ? Color.accent : Color.success))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .macPointingCursor()
                #endif

                if isExpanded {
                    if isTrustedVisualHTML {
                        HTMLContentView(htmlContent: content)
                            .frame(height: htmlHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .transition(.opacity)
                    } else {
                        Text(content)
                            .font(.appMono(10, weight: .regular))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(20)
                            .textSelection(.enabled)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke((isError ? Color.danger : (isTrustedVisualHTML ? Color.accent : Color.success)).opacity(0.15), lineWidth: 0.5)
                    )
            )
            .frame(maxWidth: isTrustedVisualHTML ? 700 : 500, alignment: .leading)

            Spacer(minLength: isTrustedVisualHTML ? 24 : 48)
        }
    }
}

// MARK: - Tool Execution Indicator

struct ToolExecutionIndicator: View {
    let status: String?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(status ?? "Executing tool...")
                .font(.appMono(11, weight: .medium))
                .foregroundStyle(Color.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.accentSoft)
                .overlay(
                    Capsule()
                        .stroke(Color.accent.opacity(0.15), lineWidth: 0.5)
                )
        )
    }
}
