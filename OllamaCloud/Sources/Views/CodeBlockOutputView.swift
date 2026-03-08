import SwiftUI

/// Scrollable list of full-featured SeerCodeBlock views shown in the center editor panel
/// when no file is selected but extracted code blocks exist.
struct CodeBlockOutputView: View {
    let blocks: [ExtractedCodeBlock]
    let onSaveToFile: (ExtractedCodeBlock) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(blocks) { block in
                    VStack(alignment: .trailing, spacing: 6) {
                        Button { onSaveToFile(block) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 10, weight: .medium))
                                Text("Save to File")
                                    .font(.appLabel(9))
                            }
                            .foregroundStyle(Color.success)
                        }
                        .buttonStyle(.plain)
                        #if os(macOS)
                        .macPointingCursor()
                        #endif

                        SeerCodeBlock(
                            language: block.language.isEmpty ? nil : block.language,
                            content: block.code
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Color.bgPrimary)
    }
}
