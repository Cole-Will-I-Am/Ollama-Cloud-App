import SwiftUI
import SwiftData

/// The Projects tab: lightweight context workspaces (name + instructions + context
/// files) that group normal chats and inject their context on every send. Mirrors
/// the manticthink website's Projects section.
struct ProjectsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    private let accountScopeKey: String
    @Query private var projects: [ChatProject]
    @Query private var conversations: [Conversation]

    @State private var selectedProject: ChatProject?
    @State private var editingProject: ChatProject?
    @State private var showNewEditor = false

    init(accountScopeKey: String = AccountScope.currentKey()) {
        self.accountScopeKey = accountScopeKey
        _projects = Query(
            filter: #Predicate<ChatProject> { project in
                project.accountScopeKey == accountScopeKey || project.accountScopeKey == ""
            },
            sort: \ChatProject.updatedAt,
            order: .reverse
        )
        _conversations = Query(
            filter: #Predicate<Conversation> { conversation in
                conversation.accountScopeKey == accountScopeKey || conversation.accountScopeKey == ""
            }
        )
    }

    private func chatCount(for project: ChatProject) -> Int {
        conversations.filter { $0.projectID == project.id }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(projects) { project in
                            Button { selectedProject = project } label: {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { deleteProject(project) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { editingProject = project } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color.accent)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.bgPrimary)
                }
            }
            .navigationTitle("Projects")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .seerLeading) {
                    Button { showNewEditor = true } label: {
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
            .navigationDestination(item: $selectedProject) { project in
                ProjectDetailView(project: project, accountScopeKey: accountScopeKey)
            }
            .sheet(isPresented: $showNewEditor) {
                ProjectEditorView(project: nil, accountScopeKey: accountScopeKey) { created in
                    selectedProject = created
                }
                #if os(macOS)
                .presentationBackground(Color.bgPrimary)
                #endif
            }
            .sheet(item: $editingProject) { project in
                ProjectEditorView(project: project, accountScopeKey: accountScopeKey) { _ in }
                #if os(macOS)
                .presentationBackground(Color.bgPrimary)
                #endif
            }
        }
    }

    private func projectRow(_ project: ChatProject) -> some View {
        let count = chatCount(for: project)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentSoft)
                    .frame(width: 40, height: 40)
                Image(systemName: "folder.fill")
                    .font(.system(size: 15, weight: .ultraLight))
                    .foregroundStyle(Color.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.app(15, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(count) chat\(count == 1 ? "" : "s")")
                    .font(.appLabel(9))
                    .luxuryTracking()
                    .foregroundStyle(Color.accent)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .ultraLight))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Color.textTertiary)
            Text("No Projects")
                .font(.app(15, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("Group chats with shared instructions and context files.")
                .font(.app(12))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { showNewEditor = true } label: {
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

    private func deleteProject(_ project: ChatProject) {
        // Detach the project's chats (keep them as normal chats), then delete.
        for conversation in conversations where conversation.projectID == project.id {
            conversation.projectID = nil
        }
        modelContext.delete(project)
        try? modelContext.save()
    }
}
