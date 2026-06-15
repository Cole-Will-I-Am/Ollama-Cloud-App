import SwiftUI
import SwiftData

/// "New Codebase" creation sheet — mirrors the manticthink website's new-codebase
/// dialog (name + Builder model + Reviewer model + reviewer toggle + rounds) in a
/// mobile-native form, replacing the bare model picker. On create it provisions the
/// Project + its hidden build conversation and hands the project back so the caller
/// can open the workspace.
struct CodebaseCreateView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let accountScopeKey: String
    let onCreated: (Project) -> Void

    @State private var name = ""
    @State private var models: [OllamaModel] = []
    @State private var builder: OllamaModel?
    @State private var reviewer: OllamaModel?
    @State private var reviewerOn = true
    @State private var rounds = 2
    @State private var isLoading = true
    @State private var loadError: String?
    @FocusState private var nameFocused: Bool

    private static let builderSystemPrompt = """
        You are a coding assistant in a project workspace. You have file tools available: \
        create_file, write_file, edit_file, read_file, delete_file, create_directory, \
        list_files, and move_file. Always use these tools to create and modify project files \
        rather than writing code in chat messages. When the user asks you to build something, \
        use create_file to make the files directly.
        """

    private var canCreate: Bool { builder != nil && !isLoading }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        intro
                        nameField
                        builderField
                        reviewerField
                        if reviewerOn { roundsField }
                        if let loadError {
                            Text(loadError).font(.app(12)).foregroundStyle(Color.danger)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Codebase")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .foregroundStyle(canCreate ? Color.accent : Color.textTertiary)
                        .disabled(!canCreate)
                }
            }
            .task { await loadModels() }
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build a codebase")
                .font(.app(20, weight: .light))
                .foregroundStyle(Color.textPrimary)
            Text("A Builder model writes and edits files with tools. An optional Reviewer critiques each round and the Builder addresses the feedback.")
                .font(.app(13))
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("NAME")
            TextField("e.g. weather-cli", text: $name)
                .font(.app(15))
                .foregroundStyle(Color.textPrimary)
                .focused($nameFocused)
                .submitLabel(.done)
                .padding(12)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
        }
    }

    private var builderField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("BUILDER MODEL")
            modelMenu(selection: $builder, placeholder: "Choose a model")
        }
    }

    private var reviewerField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $reviewerOn.animation(.snappy(duration: 0.2))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reviewer pass").font(.app(14)).foregroundStyle(Color.textPrimary)
                    Text("Critique and iterate after each round").font(.app(12)).foregroundStyle(Color.textTertiary)
                }
            }
            .tint(Color.accent)
            if reviewerOn {
                modelMenu(selection: $reviewer, placeholder: "Same as Builder")
            }
        }
    }

    private var roundsField: some View {
        HStack {
            label("MAX ROUNDS")
            Spacer()
            Stepper(value: $rounds, in: 1...4) {
                Text("\(rounds)")
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accent)
            .fixedSize()
        }
    }

    private func modelMenu(selection: Binding<OllamaModel?>, placeholder: String) -> some View {
        Menu {
            if isLoading {
                Text("Loading models…")
            } else if models.isEmpty {
                Text("No models available")
            } else {
                ForEach(models) { model in
                    Button(model.name) { selection.wrappedValue = model }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "cpu").font(.system(size: 12, weight: .ultraLight))
                Text(selection.wrappedValue?.name ?? placeholder)
                    .font(.app(14))
                    .foregroundStyle(selection.wrappedValue == nil ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.appLabel(10)).luxuryTracking().foregroundStyle(Color.textTertiary)
    }

    // MARK: - Logic

    private func loadModels() async {
        isLoading = true
        loadError = nil
        do {
            let fetched = try await OllamaAPIClient.shared.fetchModels()
            models = fetched
            pickDefaults()
            if fetched.isEmpty {
                loadError = "No models available — check your connection in Settings."
            }
        } catch {
            loadError = "Couldn't load models. You can still create and pick a model in the workspace."
        }
        isLoading = false
    }

    /// Sensible defaults, mirroring the website's cbDefaultModels: a coder model
    /// for the Builder, a different model for the Reviewer.
    private func pickDefaults() {
        guard !models.isEmpty else { return }
        func match(_ pattern: String) -> OllamaModel? {
            models.first { $0.name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        }
        let chosenBuilder = match("coder") ?? match("devstral|qwen|code") ?? models.first
        if builder == nil { builder = chosenBuilder }
        if reviewer == nil {
            reviewer = match("kimi") ?? models.first { $0.id != chosenBuilder?.id } ?? chosenBuilder
        }
    }

    private func create() {
        let conversation = Conversation(accountScopeKey: accountScopeKey)
        conversation.isProjectChat = true
        conversation.title = "Codebase Chat"
        conversation.systemPrompt = Self.builderSystemPrompt
        if let builder {
            conversation.modelName = builder.name
            conversation.apiProvider = builder.provider
        }
        modelContext.insert(conversation)

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(
            name: trimmed.isEmpty ? "New Codebase" : trimmed,
            accountScopeKey: accountScopeKey,
            conversationID: conversation.id
        )
        project.reviewerEnabled = reviewerOn
        project.reviewerModelName = reviewerOn ? reviewer?.name : nil
        project.buildRounds = rounds
        modelContext.insert(project)

        do {
            try modelContext.save()
        } catch {
            modelContext.delete(project)
            modelContext.delete(conversation)
            loadError = "Couldn't create the codebase. Please try again."
            return
        }
        Haptic.impact()
        onCreated(project)
        dismiss()
    }
}
