import SwiftUI
import SwiftData

struct ScaffoldLibraryView: View {
    let accountScopeKey: String
    let onAttach: ((ReasoningScaffold) -> Void)?
    let dismissOnAttach: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var scaffolds: [ReasoningScaffold]

    @State private var searchText = ""
    @State private var showingTemplatePicker = false
    @State private var builderSheet: BuilderSheet?
    @State private var selectedTemplate: ReasoningScaffoldTemplate?
    @State private var pendingDelete: ReasoningScaffold?
    @State private var persistenceError: String?

    private struct BuilderSheet: Identifiable {
        let id = UUID()
        let scaffold: ReasoningScaffold?
        let template: ReasoningScaffoldTemplate?
    }

    init(
        accountScopeKey: String,
        onAttach: ((ReasoningScaffold) -> Void)? = nil,
        dismissOnAttach: Bool = true
    ) {
        self.accountScopeKey = accountScopeKey
        self.onAttach = onAttach
        self.dismissOnAttach = dismissOnAttach
        _scaffolds = Query(
            filter: #Predicate<ReasoningScaffold> { scaffold in
                scaffold.accountScopeKey == accountScopeKey
            },
            sort: \ReasoningScaffold.updatedAt,
            order: .reverse
        )
    }

    private var filteredScaffolds: [ReasoningScaffold] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return scaffolds }
        return scaffolds.filter { scaffold in
            scaffold.name.localizedCaseInsensitiveContains(needle)
                || scaffold.summary.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if filteredScaffolds.isEmpty {
                    emptyState
                } else {
                    List {
                        topActions
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)

                        ForEach(filteredScaffolds) { scaffold in
                            scaffoldRow(scaffold)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .searchable(text: $searchText, prompt: "Search scaffolds")
                }
            }
            .navigationTitle("Reasoning Scaffolds")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CLOSE") { dismiss() }
                        .font(.appLabel(11))
                        .tracking(2)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .sheet(isPresented: $showingTemplatePicker, onDismiss: {
                if let t = selectedTemplate {
                    builderSheet = BuilderSheet(scaffold: nil, template: t)
                    selectedTemplate = nil
                }
            }) {
                ScaffoldTemplatePickerView { template in
                    selectedTemplate = template
                }
            }
            .sheet(item: $builderSheet) { sheet in
                ScaffoldBuilderView(
                    accountScopeKey: accountScopeKey,
                    scaffold: sheet.scaffold,
                    template: sheet.template
                )
            }
            .confirmationDialog(
                "Delete scaffold?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let pendingDelete else { return }
                    delete(pendingDelete)
                    self.pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Storage Error", isPresented: Binding(
                get: { persistenceError != nil },
                set: { _ in persistenceError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceError ?? "An unknown storage error occurred.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "brain")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.textTertiary)
            Text("No reasoning scaffolds yet")
                .font(.app(14, weight: .light))
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 10) {
                actionCapsule(title: "NEW") {
                    builderSheet = BuilderSheet(scaffold: nil, template: nil)
                }
                actionCapsule(title: "TEMPLATES") {
                    selectedTemplate = nil
                    showingTemplatePicker = true
                }
            }
            .padding(.top, 6)
        }
        .padding(24)
    }

    private var topActions: some View {
        HStack(spacing: 10) {
            actionCapsule(title: "NEW") {
                builderSheet = BuilderSheet(scaffold: nil, template: nil)
            }
            actionCapsule(title: "TEMPLATES") {
                selectedTemplate = nil
                showingTemplatePicker = true
            }
        }
        .padding(.vertical, 8)
    }

    private func actionCapsule(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appLabel(10))
                .tracking(2)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.accentSoft)
                        .overlay(Capsule().stroke(Color.border, lineWidth: 0.5))
                )
        }
    }

    private func scaffoldRow(_ scaffold: ReasoningScaffold) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(scaffold.name)
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if !scaffold.summary.isEmpty {
                    Text(scaffold.summary)
                        .font(.app(12))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                Text(lastUsedText(for: scaffold))
                    .font(.appLabel(9))
                    .tracking(1.4)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            if let onAttach {
                Button {
                    attach(scaffold, onAttach: onAttach)
                } label: {
                    Text("ATTACH")
                        .font(.appLabel(9))
                        .tracking(1.8)
                        .foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }

            Menu {
                Button("Attach") {
                    if let onAttach {
                        attach(scaffold, onAttach: onAttach)
                    }
                }
                .disabled(onAttach == nil)
                Button("Edit") {
                    builderSheet = BuilderSheet(scaffold: scaffold, template: nil)
                }
                Button("Duplicate") {
                    duplicate(scaffold)
                }
                Button("Delete", role: .destructive) {
                    pendingDelete = scaffold
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surface.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.border, lineWidth: 0.5)
                )
        )
    }

    private func attach(_ scaffold: ReasoningScaffold, onAttach: (ReasoningScaffold) -> Void) {
        onAttach(scaffold)
        if dismissOnAttach {
            dismiss()
        }
    }

    private func duplicate(_ scaffold: ReasoningScaffold) {
        let copy = ReasoningScaffold(
            accountScopeKey: scaffold.accountScopeKey,
            name: "\(scaffold.name) Copy",
            summary: scaffold.summary,
            role: scaffold.role,
            perspective: scaffold.perspective,
            tone: scaffold.tone,
            reasoningSteps: scaffold.reasoningSteps,
            outputFormat: scaffold.outputFormat,
            mustInclude: scaffold.mustInclude,
            neverInclude: scaffold.neverInclude,
            disclaimers: scaffold.disclaimers,
            prohibitedActions: scaffold.prohibitedActions
        )
        modelContext.insert(copy)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to duplicate scaffold."
        }
    }

    private func delete(_ scaffold: ReasoningScaffold) {
        let clearedCount = ReasoningScaffoldReferenceCleaner.clearReferences(
            to: scaffold.id,
            in: modelContext
        )
        modelContext.delete(scaffold)
        do {
            try modelContext.save()
            AppTelemetry.track("scaffold_deleted", metadata: ["id": scaffold.id.uuidString])
            if clearedCount > 0 {
                AppTelemetry.track(
                    "scaffold_cleared",
                    metadata: ["reason": "deleted", "conversations": "\(clearedCount)"]
                )
            }
        } catch {
            persistenceError = "Failed to delete scaffold."
        }
    }

    private func lastUsedText(for scaffold: ReasoningScaffold) -> String {
        if let lastUsedAt = scaffold.lastUsedAt {
            return "Last used \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Never used"
    }
}
