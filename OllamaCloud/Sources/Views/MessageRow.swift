import SwiftUI
import MarkdownUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct MessageRow: View {
    let message: Message
    let chatMessageCount: Int
    let showsThinkingSection: Bool
    let onEditPrompt: ((Message) -> Void)?
    let onRegenerate: ((Message) -> Void)?
    @State private var isThinkingExpanded = false
    @State private var showAssistantMarkdown = true
    @State private var assistantMarkdownDebounceTask: Task<Void, Never>?

    private static let longChatThreshold = 40
    private static let longAssistantThreshold = 900
    private static let freshAssistantWindow: TimeInterval = 4.0
    private static let assistantMarkdownDebounceNanoseconds: UInt64 = 160_000_000

    private var isToolCallMessage: Bool {
        normalizedRole == "tool_call"
    }

    private var isToolResultMessage: Bool {
        normalizedRole == "tool"
    }

    var body: some View {
        if isToolCallMessage {
            ToolCallBubble(toolCallsJSON: message.toolCallsJSON)
        } else if isToolResultMessage {
            ToolResultBubble(toolName: message.toolName, content: message.content)
        } else {
            HStack(alignment: .bottom) {
                if isUserMessage { Spacer(minLength: 48) }

                VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 0) {
                    if showsThinkingSection, let thinking = message.thinkingContent, !thinking.isEmpty {
                        thinkingSection(thinking)
                    }

                    if isUserMessage {
                        userBubble
                    } else {
                        assistantBubble
                        if let outputTokenCount = message.outputTokenCount, outputTokenCount > 0 {
                            tokenFooter(outputTokenCount)
                        }
                    }
                }
                #if os(macOS)
                .frame(maxWidth: 820, alignment: isUserMessage ? .trailing : .leading)
                #endif

                if !isUserMessage { Spacer(minLength: 48) }
            }
            .frame(maxWidth: .infinity, alignment: isUserMessage ? .trailing : .leading)
        }
    }

    private var userBubble: some View {
        Markdown(message.content)
            .markdownTheme(.seerUser)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(LinearGradient.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contextMenu {
                Button {
                    copyToClipboard(message.content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    onEditPrompt?(message)
                } label: {
                    Label("Edit Prompt", systemImage: "pencil")
                }
            }
    }

    private var assistantBubble: some View {
        let hasThinking = showsThinkingSection && !(message.thinkingContent ?? "").isEmpty
        let bubbleShape = UnevenRoundedRectangle(
            topLeadingRadius: hasThinking ? 0 : 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 20,
            topTrailingRadius: hasThinking ? 0 : 20,
            style: .continuous
        )
        return Group {
            if shouldDebounceAssistantMarkdown && !showAssistantMarkdown {
                Text(verbatim: message.content)
                    .font(.app(14))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    #if os(macOS)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    #endif
            } else {
                Markdown(message.content)
                    .markdownTheme(.seerAssistant)
                    .textSelection(.enabled)
                    #if os(macOS)
                    .transaction { transaction in
                        transaction.animation = nil
                    }
                    #endif
            }
        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .assistantMaterialBubble(shape: bubbleShape)
            .contextMenu {
                Button {
                    copyToClipboard(message.content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    onRegenerate?(message)
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            .onAppear {
                scheduleAssistantMarkdownDebounceIfNeeded()
            }
            .onDisappear {
                assistantMarkdownDebounceTask?.cancel()
            }
    }

    private var shouldDebounceAssistantMarkdown: Bool {
        guard isAssistantMessage else { return false }
        guard chatMessageCount >= Self.longChatThreshold else { return false }
        guard message.content.count >= Self.longAssistantThreshold else { return false }
        let age = Date().timeIntervalSince(message.createdAt)
        return age >= 0 && age <= Self.freshAssistantWindow
    }

    private var normalizedRole: String {
        message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isUserMessage: Bool {
        normalizedRole == "user"
    }

    private var isAssistantMessage: Bool {
        normalizedRole == "assistant"
    }

    private func scheduleAssistantMarkdownDebounceIfNeeded() {
        assistantMarkdownDebounceTask?.cancel()

        guard shouldDebounceAssistantMarkdown else {
            showAssistantMarkdown = true
            return
        }

        showAssistantMarkdown = false
        assistantMarkdownDebounceTask = Task {
            try? await Task.sleep(nanoseconds: Self.assistantMarkdownDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showAssistantMarkdown = true
            }
        }
    }

    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    isThinkingExpanded.toggle()
                }
                Haptic.selection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .ultraLight))
                    Text("THINKING")
                        .font(.appLabel(10))
                        .tracking(2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .rotationEffect(.degrees(isThinkingExpanded ? 90 : 0))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .macPointingCursor()
            #endif

            if isThinkingExpanded {
                Markdown(thinking)
                    .markdownTheme(.seerThinking)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            } else {
                Markdown(thinking)
                    .markdownTheme(.seerThinking)
                    .markdownTextStyle {
                        FontSize(11)
                        ForegroundColor(Color.textTertiary.opacity(0.4))
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20,
                style: .continuous
            )
            .stroke(Color.border, lineWidth: 0.5)
        )
        .contextMenu {
            Button {
                copyToClipboard(thinking)
            } label: {
                Label("Copy Thinking", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        Haptic.notification(.success)
    }

    private func tokenFooter(_ tokenCount: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "number")
                .font(.system(size: 8, weight: .ultraLight))
            Text("\(tokenCount) tokens")
                #if os(macOS)
                .font(.appMono(10, weight: .medium))
                #else
                .font(.app(10, weight: .medium).monospaced())
                #endif
        }
        .foregroundStyle(Color.textTertiary)
        .padding(.leading, 6)
        .padding(.top, 4)
    }
}
