import SwiftUI
import MarkdownUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct SeerCodeBlock: View {
    private static let autoCollapseLineThreshold = 20
    private static let manualCollapseLineThreshold = 6

    let language: String?
    let content: String
    @State private var isCollapsed: Bool
    @State private var isExecuting = false
    @State private var executionResult: CodeExecutionResult?

    init(language: String?, content: String) {
        self.language = language
        self.content = content
        let normalized = content.replacingOccurrences(of: "\t", with: "    ")
        let lines = max(1, normalized.components(separatedBy: .newlines).count)
        _isCollapsed = State(initialValue: lines >= Self.autoCollapseLineThreshold)
    }

    private var normalizedContent: String {
        content.replacingOccurrences(of: "\t", with: "    ")
    }

    private var languageLabel: String {
        guard let language, !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "plain text"
        }
        return language
    }

    private var lineNumberText: String {
        (1...lineCount).map(String.init).joined(separator: "\n")
    }

    private var lineCount: Int {
        max(1, normalizedContent.components(separatedBy: .newlines).count)
    }

    private var canCollapse: Bool {
        lineCount >= Self.manualCollapseLineThreshold
    }

    private var collapsedPreviewLine: String {
        normalizedContent
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(100)
            .description ?? ""
    }

    private var executableLanguage: ExecutableLanguage? {
        ExecutableLanguage.from(markdownLanguage: language)
    }

    private var canExecute: Bool {
        guard let lang = executableLanguage else { return false }
        return lang.isAvailableOnCurrentPlatform
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Color.border).frame(height: 0.5)

            if isCollapsed {
                collapsedContent
            } else {
                expandedContent
            }

            if let result = executionResult {
                outputPanel(result)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.bgPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.border, lineWidth: 0.5)
                )
        )
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text(languageLabel)
                .font(.appLabel(9))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.05)))

            Text("\(lineCount)L")
                .font(.appLabel(9))
                .foregroundStyle(Color.textTertiary)

            Spacer()

            if canCollapse {
                collapseButton
            }

            if canExecute {
                runButton
            }

            copyButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isCollapsed.toggle() }
            Haptic.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(isCollapsed ? "Expand" : "Collapse")
                    .font(.appLabel(9))
            }
            .foregroundStyle(Color.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand code block" : "Collapse code block")
    }

    private var runButton: some View {
        Button {
            runCode()
        } label: {
            HStack(spacing: 4) {
                if isExecuting {
                    ProgressView()
                        .controlSize(.mini)
                        #if os(macOS)
                        .scaleEffect(0.5)
                        #endif
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .medium))
                }
                Text("Run")
                    .font(.appLabel(9))
            }
            .foregroundStyle(Color.success)
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .accessibilityLabel("Run code")
    }

    private var copyButton: some View {
        Button {
            copyCode()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .ultraLight))
                Text("Copy")
                    .font(.appLabel(9))
            }
            .foregroundStyle(Color.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy code")
        .accessibilityHint("Copies this code block to the clipboard")
    }

    // MARK: - Content

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Code block collapsed")
                .font(.app(11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            if !collapsedPreviewLine.isEmpty {
                Text(collapsedPreviewLine)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var expandedContent: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(alignment: .top, spacing: 12) {
                Text(lineNumberText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, 2)
                    .textSelection(.disabled)

                SeerCodeSyntaxHighlighter.shared
                    .highlightCode(normalizedContent, language: language)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxHeight: 340)
    }

    // MARK: - Output Panel

    private func outputPanel(_ result: CodeExecutionResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 0.5)

            HStack {
                Label(
                    result.timedOut ? "Timed out" : (result.exitCode == 0 ? "Output" : "Error (exit \(result.exitCode))"),
                    systemImage: result.exitCode == 0 && !result.timedOut ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.appLabel(9))
                .foregroundStyle(result.exitCode == 0 && !result.timedOut ? Color.success : Color.danger)

                Spacer()

                Button {
                    withAnimation(.snappy(duration: 0.15)) { executionResult = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss output")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !result.stdout.isEmpty {
                Text(result.stdout)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, result.stderr.isEmpty ? 10 : 4)
            }

            if !result.stderr.isEmpty {
                Text(result.stderr)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.danger)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            if result.timedOut {
                Text("Execution timed out after 10 seconds")
                    .font(.app(11))
                    .foregroundStyle(Color.danger.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(Color.bgPrimary.opacity(0.6))
    }

    // MARK: - Actions

    private func runCode() {
        guard let lang = executableLanguage, !isExecuting else { return }
        isExecuting = true
        executionResult = nil
        Haptic.impact(.light)

        Task {
            let result = await CodeExecutionService.execute(code: normalizedContent, language: lang)
            await MainActor.run {
                withAnimation(.snappy(duration: 0.2)) {
                    executionResult = result
                    isExecuting = false
                }
                Haptic.notification(result.exitCode == 0 ? .success : .error)
            }
        }
    }

    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = normalizedContent
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(normalizedContent, forType: .string)
        #endif
        Haptic.notification(.success)
    }
}
