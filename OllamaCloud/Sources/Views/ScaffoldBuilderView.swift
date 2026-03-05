import SwiftUI
import SwiftData

struct ScaffoldBuilderView: View {
    let accountScopeKey: String
    let scaffold: ReasoningScaffold?
    let template: ReasoningScaffoldTemplate?
    let onSave: ((ReasoningScaffold) -> Void)?
    let preservedOutputFormat: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var summary: String
    @State private var role: String
    @State private var perspective: String
    @State private var tone: String
    @State private var reasoningStepsText: String
    @State private var mustIncludeText: String
    @State private var neverIncludeText: String
    @State private var disclaimersText: String
    @State private var prohibitedActionsText: String
    @State private var saveError: String?

    init(
        accountScopeKey: String,
        scaffold: ReasoningScaffold? = nil,
        template: ReasoningScaffoldTemplate? = nil,
        onSave: ((ReasoningScaffold) -> Void)? = nil
    ) {
        self.accountScopeKey = accountScopeKey
        self.scaffold = scaffold
        self.template = template
        self.onSave = onSave

        let sourceDraft: ReasoningScaffoldDraft
        if let scaffold {
            sourceDraft = ReasoningScaffoldCompiler.draft(from: scaffold)
        } else if let template {
            sourceDraft = template.draft
        } else {
            sourceDraft = .empty
        }
        self.preservedOutputFormat = sourceDraft.outputFormat

        _name = State(initialValue: sourceDraft.name)
        _summary = State(initialValue: sourceDraft.summary)
        _role = State(initialValue: sourceDraft.role)
        _perspective = State(initialValue: sourceDraft.perspective)
        _tone = State(initialValue: sourceDraft.tone)
        _reasoningStepsText = State(initialValue: sourceDraft.reasoningSteps.joined(separator: "\n"))
        _mustIncludeText = State(initialValue: sourceDraft.mustInclude.joined(separator: "\n"))
        _neverIncludeText = State(initialValue: sourceDraft.neverInclude.joined(separator: "\n"))
        _disclaimersText = State(initialValue: sourceDraft.disclaimers.joined(separator: "\n"))
        _prohibitedActionsText = State(initialValue: sourceDraft.prohibitedActions.joined(separator: "\n"))
    }

    private var draft: ReasoningScaffoldDraft {
        ReasoningScaffoldDraft(
            name: name,
            summary: summary,
            role: role,
            perspective: perspective,
            tone: tone,
            reasoningSteps: parseLines(reasoningStepsText),
            outputFormat: preservedOutputFormat,
            mustInclude: parseLines(mustIncludeText),
            neverInclude: parseLines(neverIncludeText),
            disclaimers: parseLines(disclaimersText),
            prohibitedActions: parseLines(prohibitedActionsText)
        )
    }

    private var issues: [ValidationIssue] {
        ReasoningScaffoldCompiler.validate(draft)
    }

    private var canSave: Bool {
        !issues.contains(where: { $0.severity == .error })
    }

    private var compiledPreview: String {
        ReasoningScaffoldCompiler.compile(draft: draft, title: draft.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !issues.isEmpty {
                        issueBlock
                    }

                    section("BASICS", helper: "Required: Name, Role, Perspective.") {
                        VStack(spacing: 14) {
                            textField("Name", text: $name, placeholder: "Support Analyst")
                            textField("Summary", text: $summary, placeholder: "What this scaffold is for")
                            textField("Role", text: $role, placeholder: "Role the model should play")
                            textEditor("Perspective", text: $perspective, minHeight: 90)
                            textField("Tone", text: $tone, placeholder: "Direct, calm, encouraging")
                        }
                        .padding(16)
                    }

                    section("REASONING STEPS", helper: "One step per line. Minimum one step.") {
                        textEditor(
                            "1) Identify the objective\n2) Analyze constraints\n3) Recommend next step",
                            text: $reasoningStepsText,
                            minHeight: 140
                        )
                        .padding(16)
                    }

                    section("OUTPUT GUIDANCE", helper: "Optional guidance, not strict formatting rules.") {
                        VStack(spacing: 14) {
                            textEditor(
                                "Helpful elements to cover (one line each)",
                                text: $mustIncludeText,
                                minHeight: 84
                            )
                            textEditor(
                                "Avoid by default (one line each)",
                                text: $neverIncludeText,
                                minHeight: 84
                            )
                        }
                        .padding(16)
                    }

                    section("SAFETY HINTS", helper: "Optional contextual safety guidance.") {
                        VStack(spacing: 14) {
                            textEditor("Disclaimers (one line each)", text: $disclaimersText, minHeight: 84)
                            textEditor(
                                "Prohibited actions (one line each)",
                                text: $prohibitedActionsText,
                                minHeight: 84
                            )
                        }
                        .padding(16)
                    }

                    section("PREVIEW", helper: "This is exactly what will be injected as scaffold context.") {
                        ScaffoldPreviewView(compiledText: compiledPreview)
                            .padding(16)
                    }
                }
                .padding(20)
            }
            .background(Color.bgPrimary)
            .navigationTitle(scaffold == nil ? "New Scaffold" : "Edit Scaffold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                        .font(.appLabel(11))
                        .tracking(2)
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("SAVE") { save() }
                        .font(.appLabel(11))
                        .tracking(2)
                        .foregroundStyle(canSave ? Color.accent : Color.textTertiary)
                        .disabled(!canSave)
                }
            }
            .alert("Unable to Save", isPresented: Binding(
                get: { saveError != nil },
                set: { _ in saveError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "An unknown storage error occurred.")
            }
        }
    }

    private var issueBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fix before saving:")
                .font(.app(12, weight: .semibold))
                .foregroundStyle(Color.danger)
            ForEach(issues) { issue in
                Text("• \(issue.message)")
                    .font(.app(12))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.danger.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.danger.opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    private func section<C: View>(_ title: String, helper: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appLabel(10))
                .foregroundStyle(Color.textTertiary)
                .labelTracking()
                .padding(.leading, 4)
            Text(helper)
                .font(.app(11))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 4)
            content()
                .chromeCard()
        }
    }

    private func textField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.appLabel(9))
                .tracking(1.5)
                .foregroundStyle(Color.textTertiary)
            TextField(placeholder, text: text)
                .font(.app(14))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.border, lineWidth: 0.5)
                        )
                )
        }
    }

    private func textEditor(_ placeholder: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: text)
                .font(.app(14))
                .foregroundStyle(Color.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.bgSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.border, lineWidth: 0.5)
                        )
                )
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.app(13))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func parseLines(_ raw: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        let normalized = draft
        let errors = ReasoningScaffoldCompiler.validate(normalized)
        guard !errors.contains(where: { $0.severity == .error }) else {
            return
        }

        let savedScaffold: ReasoningScaffold
        if let scaffold {
            ReasoningScaffoldCompiler.apply(normalized, to: scaffold)
            savedScaffold = scaffold
            AppTelemetry.track("scaffold_updated", metadata: ["id": scaffold.id.uuidString])
        } else {
            let created = ReasoningScaffoldCompiler.makeScaffold(
                accountScopeKey: accountScopeKey,
                draft: normalized
            )
            modelContext.insert(created)
            savedScaffold = created
            AppTelemetry.track("scaffold_created", metadata: ["id": created.id.uuidString])
        }

        do {
            try modelContext.save()
            onSave?(savedScaffold)
            dismiss()
        } catch {
            saveError = "Failed to save reasoning scaffold."
        }
    }
}
