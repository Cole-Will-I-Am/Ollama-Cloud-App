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
                                .font(.system(size: 15, weight: .ultraLight))
                                .foregroundStyle(Color.accent)
                            Text(conversation.modelName.isEmpty ? "None" : conversation.modelName)
                                .font(.app(14))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(16)
                    }

                    // Sampling
                    section("SAMPLING") {
                        VStack(spacing: 20) {
                            floatSlider("Temperature", $conversation.temperature, 0...2, step: 0.05,
                                        desc: "Randomness of output")
                            floatSlider("Top P", $conversation.topP, 0...1, step: 0.05,
                                        desc: "Nucleus sampling threshold")
                            intSlider("Top K", intBinding(\.topK), 1...100,
                                      desc: "Top-K token filtering")
                            floatSlider("Min P", $conversation.minP, 0...1, step: 0.01,
                                        desc: "Minimum probability filter")
                            floatSlider("Typical P", $conversation.typicalP, 0...1, step: 0.05,
                                        desc: "Locally typical sampling")
                        }
                        .padding(16)
                    }

                    // Penalties
                    section("PENALTIES") {
                        VStack(spacing: 20) {
                            floatSlider("Repeat Penalty", $conversation.repeatPenalty, 0.5...2, step: 0.05,
                                        desc: "Penalize repeated tokens")
                            intSlider("Repeat Window", intBinding(\.repeatLastN), 0...256,
                                      desc: "Lookback window for repeat penalty")
                            floatSlider("Presence Penalty", $conversation.presencePenalty, -2...2, step: 0.1,
                                        desc: "Penalize tokens already present")
                            floatSlider("Frequency Penalty", $conversation.frequencyPenalty, -2...2, step: 0.1,
                                        desc: "Penalize by frequency of use")
                        }
                        .padding(16)
                    }

                    // Engine
                    section("ENGINE") {
                        VStack(spacing: 20) {
                            intSlider("Max Tokens", intBinding(\.numPredict), 128...8192, step: 128,
                                      desc: "Maximum tokens to generate")
                            intSlider("Seed", intBinding(\.seed), 0...999999, step: 1,
                                      desc: "0 = random, any other = deterministic")
                            intSlider("Batch Size", intBinding(\.numBatch), 1...2048, step: 64,
                                      desc: "Prompt processing chunk size")
                            intSlider("Threads", intBinding(\.numThread), 0...32, step: 1,
                                      desc: "0 = auto-detect CPU threads")
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
                    Button {
                        try? modelContext.save()
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.appLabel(12))
                            .tracking(2)
                            .foregroundStyle(Color.accent)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appLabel(10))
                .foregroundStyle(Color.textTertiary)
                .labelTracking()
                .padding(.leading, 4)
            content()
                .chromeCard()
        }
    }

    private func floatSlider(_ label: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, step: Double, desc: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.app(14))
                        .foregroundStyle(Color.textPrimary)
                    Text(desc)
                        .font(.app(11))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue))
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

    private func intSlider(_ label: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, step: Double = 1, desc: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.app(14))
                        .foregroundStyle(Color.textPrimary)
                    Text(desc)
                        .font(.app(11))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text("\(Int(binding.wrappedValue))")
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

    private func intBinding(_ keyPath: ReferenceWritableKeyPath<Conversation, Int>) -> Binding<Double> {
        Binding(
            get: { Double(conversation[keyPath: keyPath]) },
            set: { conversation[keyPath: keyPath] = Int($0) }
        )
    }
}
