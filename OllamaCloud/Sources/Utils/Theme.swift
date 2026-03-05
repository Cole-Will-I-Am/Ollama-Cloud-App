import SwiftUI
import MarkdownUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics

enum Haptic {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(type)
        #endif
    }

    static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

// MARK: - Colors

extension Color {
    // Backgrounds
    static let bgPrimary = Color(red: 0.03, green: 0.03, blue: 0.04)
    static let bgSecondary = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let bgTertiary = Color(red: 0.10, green: 0.10, blue: 0.13)

    // Surfaces
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.10)
    static let surfaceElevated = Color(red: 0.10, green: 0.10, blue: 0.13)

    // Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = Color.white.opacity(0.25)

    // Accent
    static let accent = Color(red: 0.38, green: 0.50, blue: 1.0)
    static let accentSoft = Color(red: 0.38, green: 0.50, blue: 1.0).opacity(0.12)

    // Borders
    static let border = Color.white.opacity(0.05)
    static let borderLight = Color.white.opacity(0.08)

    // Semantic
    static let danger = Color(red: 1.0, green: 0.32, blue: 0.32)
    static let success = Color(red: 0.24, green: 0.86, blue: 0.56)

    // Bubbles
    static let userBubble = Color(red: 0.32, green: 0.44, blue: 1.0)
    static let assistantBubble = Color.white.opacity(0.04)

    // Shimmer
    static let shimmerLead = Color(red: 0.38, green: 0.50, blue: 1.0)
    static let shimmerTrail = Color(red: 0.55, green: 0.38, blue: 0.95)
}

// MARK: - Gradients

extension LinearGradient {
    static let accentGradient = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.48, blue: 1.0),
            Color(red: 0.55, green: 0.38, blue: 0.95)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let surfaceGradient = LinearGradient(
        colors: [Color.white.opacity(0.03), Color.white.opacity(0.0)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Font

extension Font {
    /// Primary app font — clean sans-serif (SF Pro)
    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Wide-tracked label font — for buttons, badges, small UI labels.
    /// Expanded width with light weight for that "CONTACT" / "BETA" aesthetic.
    static func appLabel(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .default).width(.expanded)
    }

    /// Display font — for large titles / hero text. Thin, slightly tracked.
    static func appDisplay(_ size: CGFloat, weight: Font.Weight = .thin) -> Font {
        .system(size: size, weight: weight, design: .default).width(.expanded)
    }
}

// MARK: - Tracking Modifier

extension View {
    /// Apply wide letter-spacing for the tracked uppercase label look.
    func labelTracking() -> some View {
        self.tracking(3)
    }

    /// Luxury-wide tracking for very small technical labels (model names, badges).
    func luxuryTracking() -> some View {
        self.tracking(4.5)
    }

    /// Subtle tracking for titles and headings.
    func titleTracking() -> some View {
        self.tracking(1.2)
    }
}

// MARK: - View Modifiers

// MARK: - Glass Material Bubble

/// Assistant bubble using thin material + subtle white stroke for OLED depth.
struct AssistantMaterialBubble<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.45)
            )
            .background(
                shape
                    .fill(Color.white.opacity(0.03))
            )
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
            )
    }
}

extension View {
    func assistantMaterialBubble<S: InsettableShape>(shape: S) -> some View {
        modifier(AssistantMaterialBubble(shape: shape))
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.15),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 200
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Chrome Card

struct ChromeCard: ViewModifier {
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(LinearGradient.surfaceGradient)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Color.border, lineWidth: 0.5)
                    )
            )
    }
}

extension View {
    func chromeCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(ChromeCard(radius: cornerRadius))
    }
}

// MARK: - Code Block Rendering

private struct SeerCodeBlock: View {
    private static let autoCollapseLineThreshold = 20
    private static let manualCollapseLineThreshold = 6

    let language: String?
    let content: String
    @State private var isCollapsed: Bool

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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(languageLabel)
                    .font(.appLabel(9))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.white.opacity(0.05))
                    )
                Text("\(lineCount)L")
                    .font(.appLabel(9))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                if canCollapse {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isCollapsed.toggle()
                        }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(Color.border)
                .frame(height: 0.5)

            if isCollapsed {
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
            } else {
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

    private func copyCode() {
        #if os(iOS)
        UIPasteboard.general.string = normalizedContent
        Haptic.notification(.success)
        #endif
    }
}

private enum SeerCodeTokenKind {
    case plain
    case keyword
    case type
    case string
    case comment
    case number
}

private struct SeerCodeToken {
    let text: String
    let kind: SeerCodeTokenKind
}

struct SeerCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    static let shared = SeerCodeSyntaxHighlighter()
    private static let maxHighlightedCharacters = 24_000

    func highlightCode(_ code: String, language: String?) -> Text {
        // Avoid expensive tokenization and deep text trees for extremely large snippets.
        if code.count > Self.maxHighlightedCharacters {
            return Text(code).foregroundColor(Self.color(for: .plain))
        }

        let tokens = Self.tokenize(code: code, language: language)
        var attributed = AttributedString()
        for token in tokens {
            var segment = AttributedString(token.text)
            segment.foregroundColor = Self.color(for: token.kind)
            attributed.append(segment)
        }
        return Text(attributed)
    }

    private static func color(for kind: SeerCodeTokenKind) -> Color {
        switch kind {
        case .plain:
            return Color.textPrimary
        case .keyword:
            return Color(red: 0.74, green: 0.62, blue: 1.0)
        case .type:
            return Color(red: 0.48, green: 0.76, blue: 1.0)
        case .string:
            return Color(red: 0.52, green: 0.88, blue: 0.64)
        case .comment:
            return Color.textTertiary
        case .number:
            return Color(red: 1.0, green: 0.74, blue: 0.42)
        }
    }

    private static func tokenize(code: String, language: String?) -> [SeerCodeToken] {
        var tokens: [SeerCodeToken] = []
        let keywords = keywordSet(for: language)

        var index = code.startIndex
        while index < code.endIndex {
            let char = code[index]

            if char == "/" && nextChar(in: code, from: index) == "/" {
                let end = consumeUntilLineBreak(in: code, from: index)
                tokens.append(SeerCodeToken(text: String(code[index..<end]), kind: .comment))
                index = end
                continue
            }

            if char == "/" && nextChar(in: code, from: index) == "*" {
                let end = consumeBlockComment(in: code, from: index)
                tokens.append(SeerCodeToken(text: String(code[index..<end]), kind: .comment))
                index = end
                continue
            }

            if char == "#" {
                let end = consumeUntilLineBreak(in: code, from: index)
                tokens.append(SeerCodeToken(text: String(code[index..<end]), kind: .comment))
                index = end
                continue
            }

            if char == "\"" || char == "'" || char == "`" {
                let end = consumeString(in: code, from: index, quote: char)
                tokens.append(SeerCodeToken(text: String(code[index..<end]), kind: .string))
                index = end
                continue
            }

            if char.isNumber {
                let end = consumeNumber(in: code, from: index)
                tokens.append(SeerCodeToken(text: String(code[index..<end]), kind: .number))
                index = end
                continue
            }

            if isWordStart(char) {
                let end = consumeWord(in: code, from: index)
                let word = String(code[index..<end])
                if keywords.contains(word) {
                    tokens.append(SeerCodeToken(text: word, kind: .keyword))
                } else if word.first?.isUppercase == true {
                    tokens.append(SeerCodeToken(text: word, kind: .type))
                } else {
                    tokens.append(SeerCodeToken(text: word, kind: .plain))
                }
                index = end
                continue
            }

            let next = code.index(after: index)
            tokens.append(SeerCodeToken(text: String(code[index..<next]), kind: .plain))
            index = next
        }

        return tokens
    }

    private static func keywordSet(for language: String?) -> Set<String> {
        let common: Set<String> = [
            "if", "else", "for", "while", "return", "switch", "case", "break", "continue",
            "let", "var", "const", "func", "class", "struct", "enum", "import", "from",
            "try", "catch", "throw", "throws", "async", "await", "in", "where", "guard",
            "public", "private", "internal", "final", "extension", "protocol", "static",
            "true", "false", "nil", "null", "undefined", "new", "this", "self"
        ]

        guard let language = language?.lowercased() else { return common }

        if language.contains("swift") {
            return common.union([
                "actor", "associatedtype", "defer", "fallthrough", "indirect", "init",
                "inout", "mutating", "nonmutating", "some", "any", "rethrows", "typealias"
            ])
        }
        if language.contains("python") || language == "py" {
            return common.union([
                "def", "elif", "lambda", "pass", "with", "as", "is", "not", "and", "or",
                "raise", "yield", "global", "nonlocal"
            ])
        }
        if language.contains("javascript") || language.contains("typescript") || language == "js" || language == "ts" {
            return common.union([
                "function", "interface", "implements", "extends", "typeof", "instanceof",
                "export", "default", "package", "delete", "void"
            ])
        }
        if language.contains("json") {
            return ["true", "false", "null"]
        }
        if language.contains("go") {
            return common.union([
                "package", "map", "chan", "select", "go", "defer", "range", "type", "interface"
            ])
        }
        if language.contains("rust") {
            return common.union([
                "fn", "impl", "match", "mod", "pub", "crate", "trait", "mut", "ref", "unsafe"
            ])
        }

        return common
    }

    private static func nextChar(in code: String, from index: String.Index) -> Character? {
        let next = code.index(after: index)
        return next < code.endIndex ? code[next] : nil
    }

    private static func consumeUntilLineBreak(in code: String, from start: String.Index) -> String.Index {
        var idx = start
        while idx < code.endIndex && !code[idx].isNewline {
            idx = code.index(after: idx)
        }
        return idx
    }

    private static func consumeBlockComment(in code: String, from start: String.Index) -> String.Index {
        var idx = code.index(start, offsetBy: 2, limitedBy: code.endIndex) ?? code.endIndex
        while idx < code.endIndex {
            if code[idx] == "*" {
                let next = code.index(after: idx)
                if next < code.endIndex && code[next] == "/" {
                    return code.index(after: next)
                }
            }
            idx = code.index(after: idx)
        }
        return code.endIndex
    }

    private static func consumeString(in code: String, from start: String.Index, quote: Character) -> String.Index {
        var idx = code.index(after: start)
        var isEscaped = false

        while idx < code.endIndex {
            let c = code[idx]
            if isEscaped {
                isEscaped = false
                idx = code.index(after: idx)
                continue
            }
            if c == "\\" {
                isEscaped = true
                idx = code.index(after: idx)
                continue
            }
            if c == quote {
                return code.index(after: idx)
            }
            idx = code.index(after: idx)
        }
        return code.endIndex
    }

    private static func consumeNumber(in code: String, from start: String.Index) -> String.Index {
        var idx = start
        while idx < code.endIndex {
            let c = code[idx]
            if c.isNumber || c == "." || c == "_" {
                idx = code.index(after: idx)
            } else {
                break
            }
        }
        return idx
    }

    private static func consumeWord(in code: String, from start: String.Index) -> String.Index {
        var idx = start
        while idx < code.endIndex {
            let c = code[idx]
            if isWord(c) {
                idx = code.index(after: idx)
            } else {
                break
            }
        }
        return idx
    }

    private static func isWordStart(_ char: Character) -> Bool {
        char.isLetter || char == "_"
    }

    private static func isWord(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }
}

extension CodeSyntaxHighlighter where Self == SeerCodeSyntaxHighlighter {
    static var seer: Self {
        SeerCodeSyntaxHighlighter.shared
    }
}

// MARK: - MarkdownUI Themes

extension MarkdownUI.Theme {
    /// Assistant bubble markdown theme — light text on dark, styled tables and code.
    static let seerAssistant = Theme()
        .text {
            ForegroundColor(Color.textPrimary)
            FontSize(15)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            ForegroundColor(Color.accent)
            FontSize(13)
        }
        .link {
            ForegroundColor(Color.accent)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontSize(20)
                    FontWeight(.semibold)
                    ForegroundColor(Color.textPrimary)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontSize(17)
                    FontWeight(.semibold)
                    ForegroundColor(Color.textPrimary)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontSize(15)
                    FontWeight(.semibold)
                    ForegroundColor(Color.textPrimary)
                }
        }
        .codeBlock { configuration in
            SeerCodeBlock(language: configuration.language, content: configuration.content)
        }
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(
                    .init(color: Color.border, width: 0.5)
                )
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.white.opacity(0.02))
                )
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(13)
                    ForegroundColor(Color.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }

    /// User bubble theme — white text.
    static let seerUser = Theme()
        .text {
            ForegroundColor(.white)
            FontSize(15)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            ForegroundColor(.white.opacity(0.85))
            FontSize(13)
        }
        .link {
            ForegroundColor(.white.opacity(0.85))
        }
        .codeBlock { configuration in
            SeerCodeBlock(language: configuration.language, content: configuration.content)
        }

    /// Thinking panel theme — subdued markdown styling.
    static let seerThinking = Theme()
        .text {
            ForegroundColor(Color.textTertiary)
            FontSize(13)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            ForegroundColor(Color.textSecondary)
            FontSize(12)
        }
        .link {
            ForegroundColor(Color.textSecondary)
        }
        .codeBlock { configuration in
            SeerCodeBlock(language: configuration.language, content: configuration.content)
        }
}
