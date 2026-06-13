import SwiftUI

/// The streaming (or saved) debate transcript.
struct DebateRunView: View {
    @ObservedObject var runner: DebateRunner
    @ObservedObject var store: DebateStore
    @State private var saved = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    ForEach(runner.turns) { turn in
                        DebateTurnView(turn: turn)
                    }
                    if let error = runner.error {
                        Text(error)
                            .font(.app(13))
                            .foregroundStyle(Color.danger)
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 1).id("debate-bottom")
                }
                .padding(18)
            }
            .onChange(of: runner.turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("debate-bottom", anchor: .bottom) }
            }
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Debate")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .seerTrailing) {
                if runner.isRunning {
                    Button { runner.stop() } label: {
                        Text("Stop").font(.app(14, weight: .medium)).foregroundStyle(Color.danger)
                    }
                } else if runner.finished {
                    Button {
                        store.save(runner.record)
                        saved = true
                        Haptic.selection()
                    } label: {
                        Text(saved ? "Saved" : "Save").font(.app(14, weight: .medium)).foregroundStyle(Color.accent)
                    }
                    .disabled(saved)
                }
            }
        }
        .onAppear { saved = store.contains(runner.recordID) }
        .onDisappear { runner.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(runner.topic)
                .font(.app(17, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(runner.modelA)  vs  \(runner.modelB)  ·  \(runner.mode.title)")
                .font(.app(11))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DebateTurnView: View {
    @ObservedObject var turn: LiveTurn

    private var accent: Color {
        switch turn.side {
        case "A": return Color.accent
        case "S": return Color(red: 0.37, green: 0.81, blue: 0.59)   // green — synthesis
        default:  return Color(red: 0.83, green: 0.60, blue: 0.43)   // amber — opponent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(turn.label) · \(turn.model)")
                .font(.app(11, weight: .medium))
                .foregroundStyle(accent)
            Text(turn.text.isEmpty ? "…" : turn.text)
                .font(.app(15))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.vertical, turn.side == "S" ? 8 : 0)
        .background(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2)
        }
    }
}
