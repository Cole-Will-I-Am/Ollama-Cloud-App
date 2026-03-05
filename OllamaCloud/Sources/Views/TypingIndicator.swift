import SwiftUI

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    private let dotColors: [Color] = [
        Color(red: 0.38, green: 0.48, blue: 1.0),
        Color(red: 0.47, green: 0.43, blue: 0.975),
        Color(red: 0.55, green: 0.38, blue: 0.95)
    ]

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(dotColors[i].opacity(0.6))
                        .frame(width: 5, height: 5)
                        .offset(y: sin(phase + Double(i) * 0.9) * 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .assistantMaterialBubble(
                shape: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
