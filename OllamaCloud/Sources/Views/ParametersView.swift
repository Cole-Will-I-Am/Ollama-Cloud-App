import SwiftUI
import SwiftData

// MARK: - Parameter Presets

enum ParameterPreset: CaseIterable {
    case creative, balanced, precise

    var label: String {
        switch self {
        case .creative: return "Creative"
        case .balanced: return "Balanced"
        case .precise: return "Precise"
        }
    }

    var icon: String {
        switch self {
        case .creative: return "paintbrush"
        case .balanced: return "equal.circle"
        case .precise: return "scope"
        }
    }

    var temperature: Double {
        switch self {
        case .creative: return 1.2
        case .balanced: return 0.7
        case .precise: return 0.2
        }
    }

    var topP: Double {
        switch self {
        case .creative: return 0.95
        case .balanced: return 0.9
        case .precise: return 0.7
        }
    }

    var topK: Int {
        switch self {
        case .creative: return 60
        case .balanced: return 40
        case .precise: return 20
        }
    }

    var minP: Double {
        switch self {
        case .creative: return 0.0
        case .balanced: return 0.0
        case .precise: return 0.05
        }
    }

    var typicalP: Double {
        switch self {
        case .creative: return 1.0
        case .balanced: return 1.0
        case .precise: return 0.9
        }
    }

    var repeatPenalty: Double {
        switch self {
        case .creative: return 1.0
        case .balanced: return 1.1
        case .precise: return 1.2
        }
    }

    var repeatLastN: Int { 64 }
    var presencePenalty: Double { 0.0 }
    var frequencyPenalty: Double { 0.0 }

    var numPredict: Int {
        switch self {
        case .creative: return 4096
        case .balanced: return 2048
        case .precise: return 2048
        }
    }

    var seed: Int { 0 }
    var numBatch: Int { 512 }
    var numThread: Int { 0 }
}

// MARK: - Parameters View

struct ParametersView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: Conversation
    @State private var errorMessage: String?
    @State private var showAdvanced = false
    @State private var showScaffoldLibrary = false
    @State private var editingScaffold: ReasoningScaffold?
    @State private var showModelPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Presets + Advanced toggle
                    presetBar

                    // Model
                    section("MODEL") {
                        Button {
                            showModelPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu")
                                    .font(.system(size: 15, weight: .ultraLight))
                                    .foregroundStyle(Color.accent)
                                Text(conversation.modelName.isEmpty ? "None" : conversation.modelName)
                                    .font(.app(14))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

                            if showAdvanced {
                                floatSlider("Min P", $conversation.minP, 0...1, step: 0.01,
                                            desc: "Minimum probability filter")
                                floatSlider("Typical P", $conversation.typicalP, 0...1, step: 0.05,
                                            desc: "Locally typical sampling")
                            }
                        }
                        .padding(16)
                    }

                    // Penalties
                    section("PENALTIES") {
                        VStack(spacing: 20) {
                            floatSlider("Repeat Penalty", $conversation.repeatPenalty, 0.5...2, step: 0.05,
                                        desc: "Penalize repeated tokens")

                            if showAdvanced {
                                intSlider("Repeat Window", intBinding(\.repeatLastN), 0...256,
                                          desc: "Lookback window for repeat penalty")
                                floatSlider("Presence Penalty", $conversation.presencePenalty, -2...2, step: 0.1,
                                            desc: "Penalize tokens already present")
                                floatSlider("Frequency Penalty", $conversation.frequencyPenalty, -2...2, step: 0.1,
                                            desc: "Penalize by frequency of use")
                            }
                        }
                        .padding(16)
                    }

                    // Engine
                    section("ENGINE") {
                        VStack(spacing: 20) {
                            intSlider("Max Tokens", intBinding(\.numPredict), 128...8192, step: 128,
                                      desc: "Maximum tokens to generate")

                            if showAdvanced {
                                intSlider("Seed", intBinding(\.seed), 0...999999, step: 1,
                                          desc: "0 = random, any other = deterministic")
                                intSlider("Batch Size", intBinding(\.numBatch), 1...2048, step: 64,
                                          desc: "Prompt processing chunk size")
                                intSlider("Threads", intBinding(\.numThread), 0...32, step: 1,
                                          desc: "0 = auto-detect CPU threads")
                            }
                        }
                        .padding(16)
                    }

                    if AppConfig.reasoningScaffoldsEnabled {
                        section("REASONING SCAFFOLD") {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 10) {
                                    Image(systemName: "brain")
                                        .font(.system(size: 13, weight: .ultraLight))
                                        .foregroundStyle(Color.accent)
                                    Text(activeScaffoldName ?? "None selected")
                                        .font(.app(14))
                                        .foregroundStyle(activeScaffoldName == nil ? Color.textTertiary : Color.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                }

                                HStack(spacing: 8) {
                                    tinyAction("Change") {
                                        showScaffoldLibrary = true
                                    }
                                    tinyAction("Edit") {
                                        editingScaffold = loadActiveScaffold()
                                    }
                                    .disabled(activeScaffoldName == nil)
                                    tinyAction("Clear") {
                                        clearActiveScaffold()
                                    }
                                    .disabled(activeScaffoldName == nil)
                                }
                            }
                            .padding(16)
                        }
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

                    // Reset
                    resetButton
                }
                .padding(20)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Parameters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            errorMessage = "Failed to save parameters."
                        }
                    } label: {
                        Text("DONE")
                            .font(.appLabel(12))
                            .tracking(2)
                            .foregroundStyle(Color.accent)
                    }
                }
            }
            .sheet(isPresented: $showScaffoldLibrary) {
                ScaffoldLibraryView(
                    accountScopeKey: AccountScope.currentKey(),
                    onAttach: { scaffold in
                        attachScaffold(scaffold)
                    },
                    dismissOnAttach: true
                )
            }
            .sheet(item: $editingScaffold) { scaffold in
                ScaffoldBuilderView(
                    accountScopeKey: AccountScope.currentKey(),
                    scaffold: scaffold
                )
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(onSelect: { model in
                    conversation.modelName = model.name
                    conversation.updatedAt = Date()
                    do {
                        try modelContext.save()
                        showModelPicker = false
                    } catch {
                        errorMessage = "Failed to save selected model."
                    }
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .alert("Storage Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown storage error occurred.")
            }
            .onChange(of: conversation.temperature) { old, new in
                if (old < 1.0 && new >= 1.0) || (old >= 1.0 && new < 1.0) {
                    Haptic.impact(.medium)
                }
            }
            .onAppear {
                refreshActiveScaffoldNameFromStore()
            }
            .onChange(of: conversation.activeScaffoldID) { _, _ in
                refreshActiveScaffoldNameFromStore()
            }
        }
    }

    // MARK: - Preset Bar

    private var presetBar: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ParameterPreset.allCases, id: \.label) { preset in
                        Button {
                            applyPreset(preset)
                            Haptic.impact(.medium)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 9, weight: .ultraLight))
                                Text(preset.label.uppercased())
                                    .font(.appLabel(9))
                                    .tracking(1.5)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(isActivePreset(preset) ? .white : Color.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isActivePreset(preset)
                                               ? AnyShapeStyle(LinearGradient.accentGradient)
                                               : AnyShapeStyle(Color.surface))
                            )
                            .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    showAdvanced.toggle()
                }
                Haptic.selection()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tuningfork")
                        .font(.system(size: 10, weight: .ultraLight))
                    Text(showAdvanced ? "LESS" : "MORE")
                        .font(.appLabel(9))
                        .tracking(1.5)
                        .lineLimit(1)
                }
                .foregroundStyle(showAdvanced ? Color.accent : Color.textTertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(showAdvanced ? Color.accentSoft : Color.surface)
                )
                .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            applyPreset(.balanced)
            Haptic.notification(.success)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .ultraLight))
                Text("RESET TO DEFAULTS")
                    .font(.appLabel(10))
                    .tracking(2)
            }
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.border, lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Helpers

    private var activeScaffoldName: String? {
        let trimmed = conversation.activeScaffoldName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func tinyAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.appLabel(9))
                .tracking(1.8)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.accentSoft)
                        .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
                )
        }
        .buttonStyle(.plain)
    }

    private func attachScaffold(_ scaffold: ReasoningScaffold) {
        conversation.activeScaffoldID = scaffold.id.uuidString
        conversation.activeScaffoldName = scaffold.name
        conversation.updatedAt = Date()
        do {
            try modelContext.save()
            AppTelemetry.track("scaffold_attached", metadata: ["id": scaffold.id.uuidString])
            Haptic.selection()
        } catch {
            errorMessage = "Failed to attach reasoning scaffold."
        }
    }

    private func clearActiveScaffold() {
        let hadScaffold = activeScaffoldName != nil
        conversation.activeScaffoldID = nil
        conversation.activeScaffoldName = nil
        conversation.updatedAt = Date()
        do {
            try modelContext.save()
            if hadScaffold {
                AppTelemetry.track("scaffold_cleared", metadata: ["reason": "manual"])
            }
            Haptic.selection()
        } catch {
            errorMessage = "Failed to clear reasoning scaffold."
        }
    }

    private func loadActiveScaffold() -> ReasoningScaffold? {
        ReasoningScaffoldResolver.resolveActiveScaffold(
            for: conversation,
            in: modelContext
        ).scaffold
    }

    private func refreshActiveScaffoldNameFromStore() {
        let resolution = ReasoningScaffoldResolver.resolveActiveScaffold(
            for: conversation,
            in: modelContext
        )
        if resolution.cleared {
            errorMessage = "Active reasoning scaffold was cleared for this account."
        }
    }

    private func isActivePreset(_ preset: ParameterPreset) -> Bool {
        conversation.temperature == preset.temperature &&
        conversation.topP == preset.topP &&
        conversation.topK == preset.topK
    }

    private func applyPreset(_ preset: ParameterPreset) {
        withAnimation(.snappy(duration: 0.2)) {
            conversation.temperature = preset.temperature
            conversation.topP = preset.topP
            conversation.topK = preset.topK
            conversation.minP = preset.minP
            conversation.typicalP = preset.typicalP
            conversation.repeatPenalty = preset.repeatPenalty
            conversation.repeatLastN = preset.repeatLastN
            conversation.presencePenalty = preset.presencePenalty
            conversation.frequencyPenalty = preset.frequencyPenalty
            conversation.numPredict = preset.numPredict
            conversation.seed = preset.seed
            conversation.numBatch = preset.numBatch
            conversation.numThread = preset.numThread
        }
    }

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

    /// Contextual hint based on parameter name and current value.
    private func liveHint(for label: String, value: Double) -> String? {
        switch label {
        case "Temperature":
            if value < 0.3 { return "Very deterministic — nearly identical outputs each time" }
            if value < 0.7 { return "Focused — predictable with slight variation" }
            if value < 1.0 { return "Balanced — natural language variability" }
            if value < 1.5 { return "Creative — more diverse and unexpected phrasing" }
            return "Wild — highly random, may lose coherence"
        case "Top P":
            if value < 0.5 { return "Very narrow — only the most likely tokens" }
            if value < 0.8 { return "Focused — moderate token diversity" }
            if value < 0.95 { return "Balanced — good range of natural expression" }
            return "Wide — nearly all tokens considered"
        case "Repeat Penalty":
            if value <= 1.0 { return "No penalty — may repeat phrases freely" }
            if value < 1.15 { return "Light — gentle discouragement of repetition" }
            if value < 1.3 { return "Moderate — noticeably avoids repeats" }
            return "Strong — aggressively avoids any repetition"
        default:
            return nil
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

            if let hint = liveHint(for: label, value: binding.wrappedValue) {
                Text(hint)
                    .font(.app(10, weight: .light))
                    .foregroundStyle(Color.accent.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.interpolate)
                    .animation(.easeOut(duration: 0.15), value: binding.wrappedValue)
            }
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
