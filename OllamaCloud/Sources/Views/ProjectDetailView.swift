import SwiftUI
import SwiftData

/// Inside a lightweight Project: its grouped chats, an Edit button for the
/// project's instructions/context files, and a "new chat in this project" action.
struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    // `let` (not @Bindable): @Model is @Observable, so reading its properties in
    // the body still tracks edits made via the editor sheet.
    let project: ChatProject
    private let accountScopeKey: String
    // Account-scoped only; projectID is filtered in Swift below. A SwiftData
    // `#Predicate` comparing the optional `projectID` to a UUID crashes at
    // evaluation time, so grouping is done client-side (same as the Chats list).
    @Query private var accountConversations: [Conversation]

    private enum ActiveSheet: Identifiable {
        case editor
        case modelPicker
        var id: Int { self == .editor ? 0 : 1 }
    }

    @State private var selectedChat: Conversation?
    @State private var activeSheet: ActiveSheet?
    @State private var pendingConversation: Conversation?
    // Chat to navigate to AFTER the model-picker sheet finishes dismissing —
    // pushing a navigationDestination while a sheet is mid-dismiss crashes SwiftUI.
    @State private var pendingNavChat: Conversation?
    @State private var persistenceError: String?

    init(project: ChatProject, accountScopeKey: String = AccountScope.currentKey()) {
        self.project = project
        self.accountScopeKey = accountScopeKey
        _accountConversations = Query(
            filter: #Predicate<Conversation> { conversation in
                conversation.accountScopeKey == accountScopeKey || conversation.accountScopeKey == ""
            },
            sort: \Conversation.updatedAt,
            order: .reverse
        )
    }

    private var projectConversations: [Conversation] {
        let pid = project.id
        return accountConversations.filter { $0.projectID == pid }
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().background(Color.border)
                if projectConversations.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(projectConversations) { conversation in
                            Button { selectedChat = conversation } label: {
                                chatRow(conversation)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { deleteChat(conversation) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.bgPrimary)
                }
                newChatBar
            }
        }
        .navigationTitle(project.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .seerTrailing) {
                Button { activeSheet = .editor } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .ultraLight))
                        .foregroundStyle(Color.textSecondary)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                .macPointingCursor()
                #endif
            }
        }
        .navigationDestination(item: $selectedChat) { conversation in
            ChatView(conversation: conversation, chatProject: project)
        }
        // A single sheet (multiple `.sheet` modifiers on one view is unreliable /
        // can crash). Navigation to a freshly created chat is deferred to
        // onDismiss so we never push while the sheet is still dismissing.
        .sheet(item: $activeSheet, onDismiss: {
            deletePendingIfEmpty()
            if let target = pendingNavChat {
                pendingNavChat = nil
                selectedChat = target
            }
        }) { sheet in
            switch sheet {
            case .editor:
                ProjectEditorView(project: project, accountScopeKey: accountScopeKey) { _ in }
                    #if os(macOS)
                    .presentationBackground(Color.bgPrimary)
                    #endif
            case .modelPicker:
                ModelPickerView(onSelect: { model in
                    if let conv = pendingConversation {
                        conv.modelName = model.name
                        conv.apiProvider = model.provider
                        do {
                            try modelContext.save()
                            pendingConversation = nil
                            pendingNavChat = conv
                            activeSheet = nil
                        } catch {
                            persistenceError = "Failed to save model selection."
                        }
                    }
                }, onCancel: {
                    activeSheet = nil
                })
                .macSheetFixedSize(SeerSheetSize.modelPicker)
            }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(project.instructions)
                    .font(.app(13))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            } else {
                Text("No custom instructions yet.")
                    .font(.app(13))
                    .foregroundStyle(Color.textTertiary)
            }
            let fileCount = project.files.count
            if fileCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10, weight: .ultraLight))
                    Text("\(fileCount) context file\(fileCount == 1 ? "" : "s")")
                        .font(.appLabel(9))
                        .luxuryTracking()
                }
                .foregroundStyle(Color.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func chatRow(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.app(15, weight: .regular))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            if !conversation.modelName.isEmpty {
                Text(conversation.modelName.uppercased())
                    .font(.appLabel(9))
                    .luxuryTracking()
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Color.textTertiary)
            Text("No chats in this project yet.")
                .font(.app(14, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newChatBar: some View {
        Button { newChat() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text("NEW CHAT IN THIS PROJECT")
                    .font(.appLabel(11))
                    .luxuryTracking()
            }
            .foregroundStyle(Color.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .macPointingCursor()
        #endif
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgPrimary)
    }

    private func newChat() {
        Haptic.impact()
        let conversation = Conversation(accountScopeKey: accountScopeKey, projectID: project.id)
        modelContext.insert(conversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to create chat."
            modelContext.delete(conversation)
            return
        }
        pendingConversation = conversation
        activeSheet = .modelPicker
    }

    private func deletePendingIfEmpty() {
        guard let pending = pendingConversation else { return }
        let hasModel = !pending.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasModel && pending.messages.isEmpty {
            modelContext.delete(pending)
            try? modelContext.save()
        }
        pendingConversation = nil
    }

    private func deleteChat(_ conversation: Conversation) {
        if selectedChat?.id == conversation.id { selectedChat = nil }
        modelContext.delete(conversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete chat."
        }
    }
}
