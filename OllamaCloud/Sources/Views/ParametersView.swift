import SwiftUI

struct ParametersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Model section
                    paramSection("MODEL") {
                        HStack {
                            Image(systemName: "cpu")
                                .font(.body.weight(.light))
                                .foregroundStyle(Color.accent)
                            Text(conversation.modelName.isEmpty ? "Not selected" : conversation.modelName)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                    }

                    // Generation section
                    paramSection("GENERATION") {
                        VStack(spacing: 18) {
                            paramSlider(
                                label: "Temperature",
                                value: String(format: "%.2f", conversation.temperature),
                                binding: $conversation.temperature,
                                range: 0...2,
                                step: 0.05
                            )
                            paramSlider(
                                label: "Top P",
                                value: String(format: "%.2f", conversation.topP),
                                binding: $conversation.topP,
                                range: 0...1,
                                step: 0.05
                            )
                            paramSlider(
                                label: "Top K",
                                value: "\(conversation.topK)",
                                binding: Binding(
                                    get: { Double(conversation.topK) },
                                    set: { conversation.topK = Int($0) }
                                ),
                                range: 1...100,
                                step: 1
                            )
                            paramSlider(
                                label: "Max Tokens",
                                value: "\(conversation.numPredict)",
                                binding: Binding(
                                    get: { Double(conversation.numPredict) },
                                    set: { conversation.numPredict = Int($0) }
                                ),
                                range: 128...8192,
                                step: 128
                            )
                        }
                        .padding(14)
                    }

                    // System prompt
                    paramSection("SYSTEM PROMPT") {
                        TextEditor(text: $conversation.systemPrompt)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(14)
                    }
                }
                .padding(16)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Parameters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private func paramSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.2)
                .padding(.leading, 4)

            content()
                .chromeCard(cornerRadius: 14)
        }
    }

    private func paramSlider(
        label: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(value)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.accent.opacity(0.1))
                    )
            }
            Slider(value: binding, in: range, step: step)
                .tint(Color.accent)
        }
    }
}
