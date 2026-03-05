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

                // Main content
                Text(rendered)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(message.role == "user" ? Color.userBubble : Color.assistantBubble)
                    .foregroundStyle(message.role == "user" ? .white : Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: message.thinkingContent != nil ? 0 : 16))
                    .clipShape(
                        .rect(
                            topLeadingRadius: message.thinkingContent != nil ? 0 : 16,
                            bottomLeadingRadius: 16,
                            bottomTrailingRadius: 16,
                            topTrailingRadius: message.thinkingContent != nil ? 0 : 16
                        )
                    )
                    .font(.body)
            }

            if message.role != "user" { Spacer(minLength: 60) }
        }
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
                        .font(.caption)
                    Text("Thinking")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(showThinking ? 90 : 0))
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.assistantBubble.opacity(0.7))
        .clipShape(
            .rect(
                topLeadingRadius: 16,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 16
            )
        )
    }
}
