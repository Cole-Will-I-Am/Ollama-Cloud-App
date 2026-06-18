import SwiftUI
import SwiftData

/// Navigation routes for the Projects tab. Deliberately value types keyed by
/// STABLE UUIDs (ChatProject.id / Conversation.id, assigned at init) — NOT the
/// @Model objects themselves. A freshly-inserted SwiftData object's identity
/// changes when it's first saved (temporary → permanent persistent ID); putting
/// such an object directly in a navigation path/`navigationDestination(item:)`
/// makes SwiftUI re-invalidate the graph every render, which is what drove the
/// Projects → pick-model flow into an infinite update loop (main-thread watchdog
/// hang, 0x8BADF00D). UUID routes are stable, so the graph settles.
enum ProjectRoute: Hashable {
    case detail(UUID)   // ChatProject.id
    case chat(UUID)     // Conversation.id
}

/// The Projects tab: lightweight context workspaces (name + instructions + context
/// files) that group normal chats and inject their context on every send. Mirrors
/// the manticthink website's Projects section.
struct ProjectsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    private let accountScopeKey: String
    @Query private var projects: [ChatProject]
    @Query private var conversations: [Conversation]

    private enum EditorTarget: Identifiable {
        case new
        case edit(ChatProject)
        var id: String { if case .edit(let p) = self { return p.id.uuidString } else { return "new" } }
    }

    // Single navigation stack for the whole tab. Detail and chat both push onto
    // this one path (by UUID), resolved to models in `.navigationDestination`.
    @State private var path: [ProjectRoute] = []
    @State private var editorTarget: EditorTarget?

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
            },
            sort: \Conversation.updatedAt,
            order: .reverse
        )
    }

    private func chatCount(for project: ChatProject) -> Int {
        conversations.filter { $0.projectID == project.id }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                if projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(projects) { project in
                            Button { path.append(.detail(project.id)) } label: {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { deleteProject(project) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { editorTarget = .edit(project) } label: {
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
                    Button { editorTarget = .new } label: {
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
                // SEER wordmark, centered in the nav bar — brands the Projects tab in
                // every state (the empty state keeps its own dead-center wordmark).
                ToolbarItem(placement: .principal) {
                    Image("SeerLogo")
                        .resizable()
                        #if os(macOS)
                        .interpolation(.high)
                        #endif
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 18)
                        .opacity(0.9)
                        .accessibilityLabel("SEER")
                }
            }
            // Both destinations are registered ONCE, at the stack root, and keyed
            // by UUID. Pushed views append routes to `path`; nothing ever holds a
            // live @Model in the navigation state.
            .navigationDestination(for: ProjectRoute.self) { route in
                switch route {
                case .detail(let projectID):
                    if let project = projects.first(where: { $0.id == projectID }) {
                        ProjectDetailView(project: project, accountScopeKey: accountScopeKey, path: $path)
                    } else {
                        missingDestination("This project is no longer available.")
                    }
                case .chat(let conversationID):
                    if let conversation = conversations.first(where: { $0.id == conversationID }) {
                        let owningProject = projects.first(where: { $0.id == conversation.projectID })
                        ChatView(conversation: conversation, chatProject: owningProject)
                    } else {
                        missingDestination("This chat is no longer available.")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                switch target {
                case .new:
                    ProjectEditorView(project: nil, accountScopeKey: accountScopeKey) { created in
                        // Stable id → safe to push immediately; no deferral needed.
                        path.append(.detail(created.id))
                    }
                    #if os(macOS)
                    .presentationBackground(Color.bgPrimary)
                    #endif
                case .edit(let project):
                    ProjectEditorView(project: project, accountScopeKey: accountScopeKey) { _ in }
                        #if os(macOS)
                        .presentationBackground(Color.bgPrimary)
                        #endif
                }
            }
        }
    }

    private func missingDestination(_ message: String) -> some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            Text(message)
                .font(.app(14, weight: .light))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(40)
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
        ZStack {
            // SEER logo, dead-center of the Projects screen.
            Image("SeerLogo")
                .resizable()
                #if os(macOS)
                .interpolation(.high)
                #endif
                .aspectRatio(contentMode: .fit)
                .frame(height: 34)
                .opacity(0.9)
                .accessibilityLabel("SEER")

            // Prompts/actions anchored toward the bottom so the logo stays centered.
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
                Button { editorTarget = .new } label: {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
