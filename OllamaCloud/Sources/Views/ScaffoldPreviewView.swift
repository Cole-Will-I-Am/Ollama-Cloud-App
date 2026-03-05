import SwiftUI

struct ScaffoldPreviewView: View {
    let compiledText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE PREVIEW")
                .font(.appLabel(10))
                .labelTracking()
                .foregroundStyle(Color.textTertiary)

            ScrollView {
                Text(compiledText.isEmpty ? "Preview will appear as you fill out fields." : compiledText)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(compiledText.isEmpty ? Color.textTertiary : Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 180, maxHeight: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.border, lineWidth: 0.5)
                    )
            )
        }
    }
}
