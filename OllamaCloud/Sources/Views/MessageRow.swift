import SwiftUI

struct MessageRow: View {
    let message: Message
    @State private var showThinking = false

    private var rendered: AttributedString {
        (try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.content)
    }

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
                }
            }

            if message.role != "user" { Spacer(minLength: 48) }
        }
    }

    private var userBubble: some View {
        Text(rendered)
            .textSelection(.enabled)
            .font(.app(15))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(LinearGradient.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var assistantBubble: some View {
        let hasThinking = !(message.thinkingContent ?? "").isEmpty
        return Text(rendered)
            .textSelection(.enabled)
            .font(.app(15))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(Color.textPrimary)
            .background(Color.assistantBubble)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: hasThinking ? 0 : 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: hasThinking ? 0 : 20,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: hasThinking ? 0 : 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    topTrailingRadius: hasThinking ? 0 : 20,
                    style: .continuous
                )
                .stroke(Color.border, lineWidth: 0.5)
            )
    }

    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    showThinking.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                    Text("Thinking")
                        .font(.app(12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .rotationEffect(.degrees(showThinking ? 90 : 0))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(thinking)
                    .font(.app(13))
                    .foregroundStyle(Color.textTertiary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
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
    }
}
