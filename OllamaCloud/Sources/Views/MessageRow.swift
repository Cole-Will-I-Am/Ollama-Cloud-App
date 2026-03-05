import SwiftUI

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 60) }

            Text(message.content)
                .textSelection(.enabled)
                .padding(12)
                .background(message.role == "user" ? Color.userBubble : Color.assistantBubble)
                .foregroundStyle(message.role == "user" ? .white : Color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .font(.body)

            if message.role != "user" { Spacer(minLength: 60) }
        }
    }
}
