import SwiftUI
import SwiftData

/// Settings for the Codebases Builder + Reviewer loop, stored on the `Project`.
struct CodebaseBuildConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: Project
    @State private var showReviewerPicker = false

    private var reviewerEnabled: Bool { project.reviewerEnabled ?? true }
    private var rounds: Int { project.buildRounds ?? 2 }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        intro
                        reviewerToggle
                        if reviewerEnabled {
                            reviewerModelRow
                            roundsRow
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Build Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .sheet(isPresented: $showReviewerPicker) {
                ModelPickerView(onSelect: { model in
                    project.reviewerModelName = model.name
                    project.updatedAt = Date()
                    try? modelContext.save()
                    showReviewerPicker = false
                })
                .macSheetFixedSize(SeerSheetSize.modelPicker)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Builder + Reviewer")
                .font(.app(18, weight: .light))
                .foregroundStyle(Color.textPrimary)
            Text("In Build mode, a Builder model edits files with tools, then a Reviewer critiques each round and the Builder addresses the feedback.")
                .font(.app(13))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reviewerToggle: some View {
        Toggle(isOn: Binding(
            get: { reviewerEnabled },
            set: { project.reviewerEnabled = $0; project.updatedAt = Date(); try? modelContext.save() }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reviewer pass").font(.app(14)).foregroundStyle(Color.textPrimary)
                Text("Critique and iterate after each Builder round").font(.app(12)).foregroundStyle(Color.textTertiary)
            }
        }
        .tint(Color.accent)
    }

    private var reviewerModelRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("REVIEWER MODEL")
            Button { showReviewerPicker = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu").font(.system(size: 12, weight: .ultraLight))
                    Text(reviewerDisplay)
                        .font(.app(13))
                        .foregroundStyle(reviewerDisplay == "Same as Builder" ? Color.textTertiary : Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .macPointingCursor()
            #endif
        }
    }

    private var reviewerDisplay: String {
        let name = project.reviewerModelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Same as Builder" : name
    }

    private var roundsRow: some View {
        HStack {
            label("MAX ROUNDS")
            Spacer()
            Stepper(value: Binding(
                get: { rounds },
                set: { project.buildRounds = max(1, min(6, $0)); project.updatedAt = Date(); try? modelContext.save() }
            ), in: 1...6) {
                Text("\(rounds)")
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accent)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.appLabel(10)).luxuryTracking().foregroundStyle(Color.textTertiary)
    }
}
