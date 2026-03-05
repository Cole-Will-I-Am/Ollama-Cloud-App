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
        let bubbleShape = UnevenRoundedRectangle(
            topLeadingRadius: hasThinking ? 0 : 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 20,
            topTrailingRadius: hasThinking ? 0 : 20,
            style: .continuous
        )
        return Text(rendered)
            .textSelection(.enabled)
            .font(.app(15))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(Color.textPrimary)
            .contentTransition(.interpolate)
            .assistantMaterialBubble(shape: bubbleShape)
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
                Text(thinking)
                    .font(.app(13))
                    .foregroundStyle(Color.textTertiary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            } else {
                Text(String(thinking.prefix(80)))
                    .font(.app(11))
                    .foregroundStyle(Color.textTertiary.opacity(0.4))
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
    }
}
