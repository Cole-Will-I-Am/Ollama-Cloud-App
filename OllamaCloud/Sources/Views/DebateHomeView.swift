import SwiftUI

/// The Debate tab: set up a head-to-head between two models, or revisit a saved one.
struct DebateHomeView: View {
    @StateObject private var runner = DebateRunner()
    @StateObject private var store = DebateStore()

    @State private var topic = ""
    @State private var models: [String] = []
    @State private var modelA = ""
    @State private var modelB = ""
    @State private var mode: DebateMode = .debate
    @State private var rounds = 2
    @State private var synthesis = true
    @State private var modelError: String?
    @State private var showRun = false

    private var canStart: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !modelA.isEmpty && !modelB.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    topicField
                    matchup
                    formatRow
                    optionsRow
                    startButton
                    if !store.debates.isEmpty { savedSection }
                }
                .padding(20)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Debate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(isPresented: $showRun) {
                DebateRunView(runner: runner, store: store)
            }
            .task { await loadModels() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI Debate")
                .font(.app(22, weight: .light))
                .foregroundStyle(Color.textPrimary)
            Text("Pose a question and let two models take turns making the case.")
                .font(.app(13))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("TOPIC")
            TextField("e.g. Should cities ban cars from downtown cores?", text: $topic, axis: .vertical)
                .lineLimit(2...4)
                .font(.app(15))
                .foregroundStyle(Color.textPrimary)
                .padding(12)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
        }
    }

    private var matchup: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("MODELS")
            HStack(spacing: 10) {
                modelMenu(selection: $modelA)
                Text("vs").font(.appLabel(10)).luxuryTracking().foregroundStyle(Color.textTertiary)
                modelMenu(selection: $modelB)
            }
            if let modelError {
                Text(modelError).font(.app(12)).foregroundStyle(Color.danger)
            }
        }
    }

    private var formatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("FORMAT")
            Picker("", selection: $mode) {
                Text("Debate (for vs against)").tag(DebateMode.debate)
                Text("Discussion").tag(DebateMode.discuss)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var optionsRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                label("ROUNDS EACH")
                Spacer()
                Picker("", selection: $rounds) {
                    ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.accent)
            }
            Toggle(isOn: $synthesis) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Closing synthesis").font(.app(14)).foregroundStyle(Color.textPrimary)
                    Text("End with an impartial summary & verdict").font(.app(12)).foregroundStyle(Color.textTertiary)
                }
            }
            .tint(Color.accent)
        }
    }

    private var startButton: some View {
        Button {
            Haptic.impact()
            runner.start(topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
                         modelA: modelA, modelB: modelB, mode: mode, rounds: rounds, synthesis: synthesis)
            showRun = true
        } label: {
            Text("Start debate")
                .font(.app(15, weight: .medium))
                .foregroundStyle(canStart ? Color.white : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canStart ? Color.accent : Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canStart)
        .buttonStyle(.plain)
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("SAVED DEBATES")
            ForEach(store.debates) { rec in
                Button {
                    runner.load(rec)
                    showRun = true
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.topic).font(.app(14)).foregroundStyle(Color.textPrimary).lineLimit(1)
                            Text("\(rec.modelA) vs \(rec.modelB) · \(rec.mode.title)")
                                .font(.appLabel(9)).luxuryTracking().foregroundStyle(Color.textTertiary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            store.delete(rec.id)
                        } label: {
                            Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modelMenu(selection: Binding<String>) -> some View {
        Menu {
            if models.isEmpty {
                Text("Loading models…")
            } else {
                ForEach(models, id: \.self) { m in
                    Button(m) { selection.wrappedValue = m }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.wrappedValue.isEmpty ? "Choose" : selection.wrappedValue)
                    .font(.app(13))
                    .foregroundStyle(selection.wrappedValue.isEmpty ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.bgSecondary, in: Capsule())
            .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.appLabel(10)).luxuryTracking().foregroundStyle(Color.textTertiary)
    }

    private func loadModels() async {
        do {
            let fetched = try await OllamaAPIClient.shared.fetchModels()
            let names = fetched.map(\.name)
            await MainActor.run {
                models = names
                if modelA.isEmpty { modelA = names.first ?? "" }
                if modelB.isEmpty { modelB = names.count > 1 ? names[1] : (names.first ?? "") }
                modelError = names.isEmpty ? "No models available — check your connection in Settings." : nil
            }
        } catch {
            await MainActor.run { modelError = "Couldn't load models. Pull to retry or check Settings." }
        }
    }
}
