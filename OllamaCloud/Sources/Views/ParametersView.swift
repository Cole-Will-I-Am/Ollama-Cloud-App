import SwiftUI

struct ParametersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Model", value: conversation.modelName.isEmpty ? "Not selected" : conversation.modelName)
                }

                Section("Generation") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", conversation.temperature))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Slider(value: $conversation.temperature, in: 0...2, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Top P")
                            Spacer()
                            Text(String(format: "%.2f", conversation.topP))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Slider(value: $conversation.topP, in: 0...1, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Top K")
                            Spacer()
                            Text("\(conversation.topK)")
                                .foregroundStyle(Color.textSecondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(conversation.topK) },
                                set: { conversation.topK = Int($0) }
                            ),
                            in: 1...100,
                            step: 1
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(conversation.numPredict)")
                                .foregroundStyle(Color.textSecondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(conversation.numPredict) },
                                set: { conversation.numPredict = Int($0) }
                            ),
                            in: 128...8192,
                            step: 128
                        )
                    }
                }

                Section("System Prompt") {
                    TextEditor(text: $conversation.systemPrompt)
                        .frame(minHeight: 100)
                        .font(.body)
                }
            }
            .navigationTitle("Parameters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
