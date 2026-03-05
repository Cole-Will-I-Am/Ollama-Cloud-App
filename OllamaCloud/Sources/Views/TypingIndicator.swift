import SwiftUI

struct TypingIndicator: View {
    private let dotColors: [Color] = [
        Color(red: 0.38, green: 0.48, blue: 1.0),
        Color(red: 0.47, green: 0.43, blue: 0.975),
        Color(red: 0.55, green: 0.38, blue: 0.95)
    ]

    var body: some View {
        HStack {
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(dotColors[i].opacity(0.7))
                            .frame(width: 6, height: 6)
                            .offset(y: sin(now * 4.0 + Double(i) * 0.8) * 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .assistantMaterialBubble(
                shape: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            Spacer()
        }
    }
}
