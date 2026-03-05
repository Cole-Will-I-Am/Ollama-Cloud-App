import SwiftUI

struct TypingIndicator: View {
    @State private var activeDot = 0

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.textSecondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(activeDot == index ? 1.3 : 1.0)
                        .opacity(activeDot == index ? 1.0 : 0.3)
                        .animation(.easeInOut(duration: 0.3), value: activeDot)
                }
            }
            .padding(12)
            .background(Color.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                Task { @MainActor in
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
    }
}
