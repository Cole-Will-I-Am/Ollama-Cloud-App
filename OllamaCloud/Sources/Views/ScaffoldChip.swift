import SwiftUI

struct ScaffoldChip: View {
    let name: String
    let onSwap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 10, weight: .ultraLight))
                Text("Scaffold: \(name)")
                    .font(.app(11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.textSecondary)

            Spacer(minLength: 4)

            Button("Swap") { onSwap() }
                .font(.appLabel(9))
                .tracking(1.5)
                .foregroundStyle(Color.accent)

            Rectangle()
                .fill(Color.border)
                .frame(width: 0.5, height: 14)

            Button("Clear") { onClear() }
                .font(.appLabel(9))
                .tracking(1.5)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color.surface)
                .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
        )
    }
}
