import SwiftUI

struct ParametersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Model
                    section("MODEL") {
                        HStack(spacing: 12) {
                            Image(systemName: "cpu")
                                .font(.system(size: 15, weight: .light, design: .rounded))
                                .foregroundStyle(Color.accent)
                            Text(conversation.modelName.isEmpty ? "None" : conversation.modelName)
                                .font(.app(14))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(16)
                    }

                    // Generation
                    section("GENERATION") {
                        VStack(spacing: 20) {
                            slider(label: "Temperature", value: String(format: "%.2f", conversation.temperature),
                                   binding: $conversation.temperature, range: 0...2, step: 0.05)
                            slider(label: "Top P", value: String(format: "%.2f", conversation.topP),
                                   binding: $conversation.topP, range: 0...1, step: 0.05)
                            slider(label: "Top K", value: "\(conversation.topK)",
                                   binding: Binding(get: { Double(conversation.topK) }, set: { conversation.topK = Int($0) }),
                                   range: 1...100, step: 1)
                            slider(label: "Max Tokens", value: "\(conversation.numPredict)",
                                   binding: Binding(get: { Double(conversation.numPredict) }, set: { conversation.numPredict = Int($0) }),
                                   range: 128...8192, step: 128)
                        }
                        .padding(16)
                    }

                    // System prompt
                    section("SYSTEM PROMPT") {
                        TextEditor(text: $conversation.systemPrompt)
                            .font(.app(14))
                            .foregroundStyle(Color.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .padding(16)
                    }
                }
                .padding(20)
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
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)
                .padding(.leading, 4)
            content()
                .chromeCard()
        }
    }

    private func slider(label: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.app(14))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(value)
                    .font(.app(12, weight: .medium).monospaced())
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentSoft))
            }
            Slider(value: binding, in: range, step: step)
                .tint(Color.accent)
        }
    }
}
