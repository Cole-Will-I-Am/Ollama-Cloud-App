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
    @State private var showsInputPanel = false
    @State private var inputValues = ""

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

    private var hasInputValues: Bool {
        !inputValues.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputValueLineCount: Int {
        let normalized = inputValues
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .newlines)
        guard !normalized.isEmpty else { return 0 }
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).count
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

            if canExecute && showsInputPanel {
                inputPanel
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
        #if os(macOS)
        .animation(.snappy(duration: 0.2), value: isCollapsed)
        #endif
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
                inputButton
                runButton
            } else if executableLanguage != nil {
                // Runnable language, just not on this platform (e.g. Python/Shell on iOS).
                Text("Runs on macOS")
                    .font(.appLabel(9))
                    .foregroundStyle(Color.textTertiary)
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
        #if os(macOS)
        .macPointingCursor()
        #endif
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
        #if os(macOS)
        .macPointingCursor()
        #endif
        .disabled(isExecuting)
        .accessibilityLabel("Run code")
    }

    private var inputButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                showsInputPanel.toggle()
            }
            Haptic.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.system(size: 9, weight: .medium))
                Text("Input")
                    .font(.appLabel(9))
                if hasInputValues {
                    Text("\(inputValueLineCount)")
                        .font(.appLabel(8))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accent.opacity(0.95)))
                }
            }
            .foregroundStyle(hasInputValues ? Color.accent : Color.textSecondary)
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .macPointingCursor()
        #endif
        .accessibilityLabel(showsInputPanel ? "Hide input values" : "Show input values")
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
        #if os(macOS)
        .macPointingCursor()
        #endif
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
                    #if os(macOS)
                    .font(.appMono(12))
                    #endif
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
                    #if os(macOS)
                    .font(.appMono(11))
                    #endif
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .padding(.trailing, 2)
                    .textSelection(.disabled)

                SeerCodeSyntaxHighlighter.shared
                    .highlightCode(normalizedContent, language: language)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    #if os(macOS)
                    .font(.appMono(13))
                    #endif
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            #if os(macOS)
            .fixedSize(horizontal: true, vertical: false)
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxHeight: 340)
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Color.border).frame(height: 0.5)

            HStack(spacing: 8) {
                Label("Input values", systemImage: "text.line.first.and.arrowtriangle.forward")
                    .font(.appLabel(9))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                if hasInputValues {
                    Button {
                        inputValues = ""
                        Haptic.selection()
                    } label: {
                        Text("Clear")
                            .font(.appLabel(9))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .macPointingCursor()
                    #endif
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Text("One line per value. Values are consumed in order for stdin/prompt/readLine.")
                .font(.app(11))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 12)

            TextEditor(text: $inputValues)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                #if os(macOS)
                .font(.appMono(12))
                #endif
                .frame(minHeight: 76, maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.border, lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    // MARK: - Output Panel

    private func outputPanel(_ result: CodeExecutionResult) -> some View {
        let status = statusPresentation(for: result)
        let combined = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color.border).frame(height: 0.5)

            HStack(spacing: 12) {
                Label(
                    status.title,
                    systemImage: status.systemImage
                )
                .font(.appLabel(9))
                .foregroundStyle(status.color)

                Spacer()

                if !combined.isEmpty {
                    Button {
                        copyText(combined)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .macPointingCursor()
                    #endif
                    .accessibilityLabel("Copy output")
                }

                Button {
                    withAnimation(.snappy(duration: 0.15)) { executionResult = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .macPointingCursor()
                #endif
                .accessibilityLabel("Dismiss output")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Scroll long output instead of letting it grow the chat unbounded.
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !result.stdout.isEmpty {
                        Text(result.stdout)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            #if os(macOS)
                            .font(.appMono(12))
                            #endif
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !result.stderr.isEmpty {
                        Text(result.stderr)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            #if os(macOS)
                            .font(.appMono(12))
                            #endif
                            .foregroundStyle(Color.danger)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if result.timedOut {
                        Text("Execution timed out")
                            .font(.app(11))
                            .foregroundStyle(Color.danger.opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 240)
        }
        .background(Color.bgPrimary.opacity(0.6))
    }

    private func statusPresentation(for result: CodeExecutionResult) -> (title: String, systemImage: String, color: Color) {
        if result.timedOut {
            return ("Timed out", "exclamationmark.triangle", Color.danger)
        }

        if isInputExhaustedError(result.stderr) {
            return ("More Input Needed", "text.badge.plus", Color.textSecondary)
        }

        if isNodeInputUnsupportedError(result.stderr) {
            return ("Input API Unsupported", "info.circle", Color.textSecondary)
        }

        if isNodeNotInstalledHint(result.stderr) {
            return ("Node.js Not Found", "shippingbox", Color.textSecondary)
        }

        if result.exitCode == 0 {
            return ("Output", "checkmark.circle", Color.success)
        }

        return ("Error (exit \(result.exitCode))", "exclamationmark.triangle", Color.danger)
    }

    private func isInputExhaustedError(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("program requested more input than provided")
            || lower.contains("program needed more input lines than provided")
    }

    private func isNodeInputUnsupportedError(_ stderr: String) -> Bool {
        stderr.lowercased().contains("node-style interactive stdin/readline is not supported on ios javascriptcore")
    }

    private func isNodeNotInstalledHint(_ stderr: String) -> Bool {
        stderr.contains("Node.js not found") || stderr.contains("Install Node.js to run this code")
    }

    // MARK: - Actions

    private func runCode() {
        guard let lang = executableLanguage, !isExecuting else { return }
        let codeSnapshot = normalizedContent
        let stdinSnapshot = inputValues
        isExecuting = true
        executionResult = nil
        Haptic.impact(.light)

        Task {
            let result = await CodeExecutionService.execute(
                code: codeSnapshot,
                language: lang,
                stdin: stdinSnapshot
            )
            await MainActor.run {
                withAnimation(.snappy(duration: 0.2)) {
                    executionResult = result
                    isExecuting = false
                }
                Haptic.notification(result.exitCode == 0 ? .success : .error)
            }
        }
    }

    private func copyCode() { copyText(normalizedContent) }

    private func copyText(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
        Haptic.notification(.success)
    }
}
