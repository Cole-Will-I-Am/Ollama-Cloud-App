import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Create or edit a lightweight Project: its name, custom instructions, and
/// attached context files. Mirrors the website's project editor + saveProject.
struct ProjectEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new project.
    let project: ChatProject?
    let accountScopeKey: String
    let onSaved: (ChatProject) -> Void

    @State private var name: String = ""
    @State private var instructions: String = ""
    @State private var draftFiles: [DraftFile] = []
    @State private var pasteName: String = ""
    @State private var pasteContent: String = ""
    @State private var showFileImporter = false
    @State private var importError: String?

    private struct DraftFile: Identifiable {
        let id: UUID
        var name: String
        var content: String
        var byteCount: Int { content.utf8.count }
    }

    private static let sizeWarnThreshold = 512 * 1024

    private var totalBytes: Int { draftFiles.reduce(0) { $0 + $1.byteCount } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        nameField
                        instructionsField
                        filesSection
                        pasteSection
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(Color.accent)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText, .utf8PlainText, .text, .sourceCode, .json, .xml, .commaSeparatedText],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
            .alert("Import Error", isPresented: Binding(
                get: { importError != nil },
                set: { _ in importError = nil }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "Could not import the file.")
            }
            .onAppear(perform: populateFromProject)
        }
    }

    // MARK: - Sections

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("NAME")
            TextField("Project name", text: $name)
                .font(.app(15))
                .foregroundStyle(Color.textPrimary)
                .padding(12)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
        }
    }

    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("CUSTOM INSTRUCTIONS")
            TextField("How should the model behave in this project?", text: $instructions, axis: .vertical)
                .lineLimit(3...10)
                .font(.app(14))
                .foregroundStyle(Color.textPrimary)
                .padding(12)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.border, lineWidth: 0.5))
        }
    }

    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("CONTEXT FILES")
                Spacer()
                if !draftFiles.isEmpty {
                    Text(fmtBytes(totalBytes))
                        .font(.appLabel(9))
                        .luxuryTracking()
                        .foregroundStyle(totalBytes > Self.sizeWarnThreshold ? Color.danger : Color.textTertiary)
                }
            }
            if draftFiles.isEmpty {
                Text("No files yet.")
                    .font(.app(13))
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(draftFiles) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        Text(file.name)
                            .font(.app(13))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(fmtBytes(file.byteCount))
                            .font(.appLabel(9))
                            .foregroundStyle(Color.textTertiary)
                        Button {
                            draftFiles.removeAll { $0.id == file.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            Button { showFileImporter = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("ADD FILE")
                        .font(.appLabel(10))
                        .luxuryTracking()
                }
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .macPointingCursor()
            #endif
        }
    }

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("OR PASTE TEXT")
            TextField("file name (e.g. notes.md)", text: $pasteName)
                .font(.app(13))
                .foregroundStyle(Color.textPrimary)
                .padding(10)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border, lineWidth: 0.5))
            TextField("paste content here…", text: $pasteContent, axis: .vertical)
                .lineLimit(3...10)
                .font(.app(13))
                .foregroundStyle(Color.textPrimary)
                .padding(10)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.border, lineWidth: 0.5))
            Button { addPastedFile() } label: {
                Text("ADD PASTED FILE")
                    .font(.appLabel(10))
                    .luxuryTracking()
                    .foregroundStyle(canAddPaste ? Color.accent : Color.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.accentSoft.opacity(canAddPaste ? 1 : 0.4), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canAddPaste)
            #if os(macOS)
            .macPointingCursor()
            #endif
        }
    }

    private var canAddPaste: Bool {
        !pasteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.appLabel(10)).luxuryTracking().foregroundStyle(Color.textTertiary)
    }

    // MARK: - Actions

    private func populateFromProject() {
        guard let project, name.isEmpty, instructions.isEmpty, draftFiles.isEmpty else { return }
        name = project.name == "New Project" ? "" : project.name
        instructions = project.instructions
        draftFiles = project.files
            .sorted { $0.createdAt < $1.createdAt }
            .map { DraftFile(id: $0.id, name: $0.name, content: $0.content) }
    }

    private func addPastedFile() {
        let trimmedName = pasteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = trimmedName.isEmpty ? "pasted-\(draftFiles.count + 1).txt" : trimmedName
        draftFiles.append(DraftFile(id: UUID(), name: fileName, content: pasteContent))
        pasteName = ""
        pasteContent = ""
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url),
                      let text = String(data: data, encoding: .utf8) else {
                    importError = "“\(url.lastPathComponent)” isn’t a readable text file."
                    continue
                }
                draftFiles.append(DraftFile(id: UUID(), name: url.lastPathComponent, content: text))
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Untitled project" : trimmedName

        let target: ChatProject
        if let project {
            target = project
            target.name = finalName
            target.instructions = instructions
            target.updatedAt = Date()
            // Replace context files wholesale.
            for existing in project.files { modelContext.delete(existing) }
            target.files = []
        } else {
            target = ChatProject(name: finalName, accountScopeKey: accountScopeKey, instructions: instructions)
            modelContext.insert(target)
        }

        for draft in draftFiles {
            let file = ProjectContextFile(name: draft.name, content: draft.content, project: target)
            modelContext.insert(file)
        }

        do {
            try modelContext.save()
        } catch {
            importError = "Could not save the project — storage may be full."
            return
        }
        onSaved(target)
        dismiss()
    }

    private func fmtBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1_048_576 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.2f MB", Double(n) / 1_048_576)
    }
}
