import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    private let accountScopeKey: String
    @Query private var projects: [Project]
    @Binding var selection: Project?
    @Binding var createToken: Int
    @State private var showModelPicker = false
    @State private var pendingProject: Project?
    @State private var persistenceError: String?
    @State private var renamingProject: Project?
    @State private var renameText = ""
    #if os(macOS)
    @State private var hoveredProjectID: UUID?
    @State private var isHoveringNewButton = false
    #endif

    init(
        selection: Binding<Project?>,
        createToken: Binding<Int>,
        accountScopeKey: String = AccountScope.currentKey()
    ) {
        self._selection = selection
        self._createToken = createToken
        self.accountScopeKey = accountScopeKey
        _projects = Query(
            filter: #Predicate<Project> { project in
                project.accountScopeKey == accountScopeKey
                || project.accountScopeKey == ""
            },
            sort: \Project.updatedAt,
            order: .reverse
        )
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(projects) { project in
                projectRow(project)
            }
            .onDelete(perform: deleteProjects)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        #if os(macOS)
        .animation(.easeOut(duration: 0.14), value: selection?.id)
        .safeAreaInset(edge: .bottom) {
            Button {
                newProject()
            } label: {
                Text("+ NEW PROJECT")
                    .font(.appLabel(11))
                    .luxuryTracking()
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .macHoverSurface(isHoveringNewButton, radius: 24, fill: Color.white.opacity(0.03))
            .macPointingCursor(isHoveringNewButton)
            .onHover { isHoveringNewButton = $0 }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.bgPrimary)
        }
        #endif
        .navigationTitle("Projects")
        .task(id: createToken) {
            guard createToken > 0 else { return }
            newProject()
            createToken = 0
        }
        .toolbar {
            ToolbarItem(placement: .seerLeading) {
                Button {
                    newProject()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .ultraLight))
                        .foregroundStyle(Color.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .macPointingCursor()
                #endif
            }
        }
        .sheet(isPresented: $showModelPicker, onDismiss: {
            pendingProject = nil
        }) {
            ModelPickerView(onSelect: { model in
                if let proj = pendingProject {
                    // Set the model on the project's hidden conversation
                    let convID = proj.conversationID
                    let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convID })
                    if let conv = try? modelContext.fetch(descriptor).first {
                        conv.modelName = model.name
                        conv.apiProvider = model.provider
                    }
                    do {
                        try modelContext.save()
                        selection = proj
                    } catch {
                        persistenceError = "Failed to save model selection."
                    }
                }
                pendingProject = nil
                showModelPicker = false
            }, onCancel: {
                // Keep the project even without a model — open it so it doesn't
                // silently vanish. A model can be chosen later in the workspace.
                selection = pendingProject
                pendingProject = nil
                showModelPicker = false
            })
            .macSheetFixedSize(SeerSheetSize.modelPicker)
        }
        .alert("Storage Error", isPresented: Binding(
            get: { persistenceError != nil },
            set: { _ in persistenceError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown storage error occurred.")
        }
        .alert("Rename Project", isPresented: Binding(
            get: { renamingProject != nil },
            set: { if !$0 { renamingProject = nil } }
        )) {
            TextField("Project name", text: $renameText)
            Button("Rename") {
                if let proj = renamingProject {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        proj.name = trimmed
                        proj.updatedAt = Date()
                        try? modelContext.save()
                    }
                }
                renamingProject = nil
            }
            Button("Cancel", role: .cancel) {
                renamingProject = nil
            }
        }
        .overlay {
            if projects.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "folder")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Color.textTertiary)
                    Text("No Projects")
                        .font(.app(15, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                    Button {
                        newProject()
                    } label: {
                        Text("+ NEW PROJECT")
                            .font(.appLabel(11))
                            .luxuryTracking()
                            .foregroundStyle(Color.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentSoft, in: Capsule())
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .macPointingCursor()
                    #endif
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func projectRow(_ project: Project) -> some View {
        #if os(macOS)
        let rowSpacing: CGFloat = 12
        let avatarSize: CGFloat = 36
        let avatarIconSize: CGFloat = 14
        let rowVerticalPadding: CGFloat = 7
        #else
        let rowSpacing: CGFloat = 14
        let avatarSize: CGFloat = 40
        let avatarIconSize: CGFloat = 15
        let rowVerticalPadding: CGFloat = 6
        #endif

        let fileCount = project.files.filter { !$0.isDirectory }.count

        let row = NavigationLink(value: project) {
            HStack(spacing: rowSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentSoft)
                        .frame(width: avatarSize, height: avatarSize)
                    Image(systemName: "folder.fill")
                        .font(.system(size: avatarIconSize, weight: .ultraLight))
                        .foregroundStyle(Color.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.app(15, weight: .regular))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                        .font(.appLabel(9))
                        .luxuryTracking()
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.vertical, rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowSeparator(.hidden)
        .contextMenu {
            Button {
                renameText = project.name
                renamingProject = project
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleteProject(project)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteProject(project)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        #if os(macOS)
        row
            .onHover { hovering in
                if hovering {
                    hoveredProjectID = project.id
                } else if hoveredProjectID == project.id {
                    hoveredProjectID = nil
                }
            }
            .listRowBackground(projectRowBackground(for: project))
            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        #else
        row
            .listRowBackground(Color.clear)
        #endif
    }

    private func projectRowBackground(for project: Project) -> Color {
        #if os(macOS)
        if selection?.id == project.id {
            return Color.accentSoft.opacity(0.5)
        }
        if hoveredProjectID == project.id {
            return Color.surface.opacity(0.8)
        }
        #endif
        return Color.clear
    }

    private func newProject() {
        guard !showModelPicker else { return }
        Haptic.impact()

        // Create the hidden conversation for the project chat
        let conversation = Conversation(accountScopeKey: accountScopeKey)
        conversation.isProjectChat = true
        conversation.title = "Project Chat"
        conversation.systemPrompt = """
            You are a coding assistant in a project workspace. You have file tools available: \
            create_file, write_file, edit_file, read_file, delete_file, create_directory, \
            list_files, and move_file. Always use these tools to create and modify project files \
            rather than writing code in chat messages. When the user asks you to build something, \
            use create_file to make the files directly.
            """
        modelContext.insert(conversation)

        let project = Project(
            name: "New Project",
            accountScopeKey: accountScopeKey,
            conversationID: conversation.id
        )
        modelContext.insert(project)

        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to create project."
            modelContext.delete(project)
            modelContext.delete(conversation)
            return
        }

        pendingProject = project
        showModelPicker = true
    }

    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            let project = projects[index]
            deleteProject(project)
        }
    }

    private func deleteProject(_ project: Project) {
        if selection?.id == project.id { selection = nil }

        // Also delete the hidden conversation
        let convID = project.conversationID
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convID })
        if let conv = try? modelContext.fetch(descriptor).first {
            modelContext.delete(conv)
        }

        modelContext.delete(project)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete project."
        }
    }
}
