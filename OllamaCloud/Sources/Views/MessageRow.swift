import SwiftUI

struct MessageRow: View {
    let message: Message
    @State private var showThinking = false

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.content)
    }

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            VStack(alignment: .leading, spacing: 0) {
                // Thinking disclosure
                if let thinking = message.thinkingContent, !thinking.isEmpty {
                    thinkingSection(thinking)
                }

                // Content
                if message.role == "user" {
                    userBubble
                } else {
                    assistantBubble
                }
            }

            if message.role != "user" { Spacer(minLength: 60) }
        }
    }

    private var userBubble: some View {
        Text(rendered)
            .textSelection(.enabled)
            .padding(12)
            .font(.body)
            .foregroundStyle(.white)
            .background(
                LinearGradient.accentGradient
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    private var assistantBubble: some View {
        let hasThinking = message.thinkingContent != nil && !(message.thinkingContent?.isEmpty ?? true)
        return Text(rendered)
            .textSelection(.enabled)
            .padding(12)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .background(Color.assistantBubble)
            .clipShape(
                .rect(
                    topLeadingRadius: hasThinking ? 0 : 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: hasThinking ? 0 : 16
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: hasThinking ? 0 : 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: hasThinking ? 0 : 16
                )
                .stroke(Color.border, lineWidth: 0.5)
            )
    }

    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showThinking.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Thinking")
                        .font(.caption2.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(showThinking ? 90 : 0))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(
            .rect(
                topLeadingRadius: 16,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 16
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 16
            )
            .stroke(Color.border, lineWidth: 0.5)
        )
    }
}
