import SwiftUI
import MarkdownUI
#if canImport(UIKit)
import UIKit
#endif

struct MessageRow: View {
    let message: Message
    let onEditPrompt: ((Message) -> Void)?
    let onRegenerate: ((Message) -> Void)?
    @State private var showThinking = false

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == "user" { Spacer(minLength: 48) }

            VStack(alignment: .leading, spacing: 0) {
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    thinkingSection(thinking)
                }

                if message.role == "user" {
                    userBubble
                } else {
                    assistantBubble
                    if let outputTokenCount = message.outputTokenCount, outputTokenCount > 0 {
                        tokenFooter(outputTokenCount)
                    }
                }
            }

            if message.role != "user" { Spacer(minLength: 48) }
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
        let hasThinking = !(message.thinkingContent ?? "").isEmpty
        let bubbleShape = UnevenRoundedRectangle(
            topLeadingRadius: hasThinking ? 0 : 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 20,
            topTrailingRadius: hasThinking ? 0 : 20,
            style: .continuous
        )
        return Markdown(message.content)
            .markdownTheme(.seerAssistant)
            .textSelection(.enabled)
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
    }

    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    showThinking.toggle()
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
                        .rotationEffect(.degrees(showThinking ? 90 : 0))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showThinking {
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
        Haptic.notification(.success)
        #endif
    }

    private func tokenFooter(_ tokenCount: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "number")
                .font(.system(size: 8, weight: .ultraLight))
            Text("\(tokenCount) tokens")
                .font(.app(10, weight: .medium).monospaced())
        }
        .foregroundStyle(Color.textTertiary)
        .padding(.leading, 6)
        .padding(.top, 4)
    }
}
