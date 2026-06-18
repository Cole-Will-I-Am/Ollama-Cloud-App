import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    private let accountScopeKey: String
    @Query private var conversations: [Conversation]
    @Binding var selection: Conversation?
    @State private var showModelPicker = false
    @State private var pendingConversation: Conversation?
    @State private var persistenceError: String?
    @State private var searchText = ""
    #if os(macOS)
    @State private var hoveredConversationID: UUID?
    @State private var isHoveringNewChatButton = false
    #endif

    init(selection: Binding<Conversation?>, accountScopeKey: String = AccountScope.currentKey()) {
        self._selection = selection
        self.accountScopeKey = accountScopeKey
        _conversations = Query(
            filter: #Predicate<Conversation> { conversation in
                (conversation.accountScopeKey == accountScopeKey
                 || conversation.accountScopeKey == "")
                // Include normal chats explicitly: isProjectChat is an optional
                // Bool that is nil for normal chats, and SwiftData's SQLite
                // translation of `!= true` excludes NULL rows — which silently
                // hid every normal conversation from the list.
                && (conversation.isProjectChat == nil || conversation.isProjectChat == false)
            },
            sort: \Conversation.updatedAt,
            order: .reverse
        )
    }

    private var sortedConversations: [Conversation] {
        conversations
            // Lightweight-project chats live under their project (Projects tab),
            // not in the global Chats list. Filtered here rather than in the
            // @Query predicate, which hit the type-checker's complexity limit.
            .filter { $0.projectID == nil }
            .sorted {
                let lhsPinned = $0.isPinned == true
                let rhsPinned = $1.isPinned == true
                if lhsPinned != rhsPinned {
                    return lhsPinned && !rhsPinned
                }
                return $0.updatedAt > $1.updatedAt
            }
    }

    /// `sortedConversations` narrowed by the search field. Matches the chat
    /// title or the text of any message in the conversation (case-insensitive).
    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sortedConversations }
        return sortedConversations.filter { conversation in
            if conversation.title.lowercased().contains(query) { return true }
            return conversation.messages.contains { $0.content.lowercased().contains(query) }
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List(selection: $selection) {
            #if os(macOS)
            if !sortedConversations.isEmpty {
                Section {
                    EmptyView()
                } header: {
                    HStack {
                        Spacer()
                        Image("SeerEmblem")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 20)
                        Spacer()
                    }
                    .listRowBackground(Color.bgPrimary)
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 4)
                }
            }
            #endif
            ForEach(filteredConversations) { conversation in
                conversationRow(conversation)
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .searchable(text: $searchText, prompt: "Search chats")
        #if os(macOS)
        .animation(.easeOut(duration: 0.14), value: selection?.id)
        .safeAreaInset(edge: .bottom) {
            Button {
                newConversation()
            } label: {
                Text("+ NEW CHAT")
                    .font(.appLabel(11))
                    .luxuryTracking()
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)
            .macHoverSurface(isHoveringNewChatButton, radius: 24, fill: Color.white.opacity(0.03))
            .macPointingCursor(isHoveringNewChatButton)
            .onHover { isHoveringNewChatButton = $0 }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.bgPrimary)
        }
        #endif
        .navigationTitle("Chats")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            backfillLegacyConversationScopes()
            clearSelectionIfOutOfScope()
        }
        .toolbar {
            ToolbarItem(placement: .seerLeading) {
                Button {
                    newConversation()
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
            // SEER wordmark in the nav bar, same size as the Projects & Debate tabs.
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
        .sheet(isPresented: $showModelPicker, onDismiss: {
            deletePendingConversationIfEmpty()
            pendingConversation = nil
        }) {
            ModelPickerView(onSelect: { model in
                if let conv = pendingConversation {
                    conv.modelName = model.name
                    conv.apiProvider = model.provider
                    do {
                        try modelContext.save()
                        selection = conv
                    } catch {
                        persistenceError = "Failed to save model selection."
                    }
                }
                pendingConversation = nil
                showModelPicker = false
            }, onCancel: {
                deletePendingConversationIfEmpty()
                pendingConversation = nil
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
        .overlay {
            if sortedConversations.isEmpty {
                VStack(spacing: 14) {
                    Image("SeerEmblem")
                        .resizable()
                        #if os(macOS)
                        .interpolation(.high)
                        #endif
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 48)
                    Text("Let's Party")
                        .font(.app(15, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                }
            } else if isSearching && filteredConversations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(Color.textTertiary)
                    Text("No chats match \u{201C}\(searchText)\u{201D}")
                        .font(.app(14, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        #if os(macOS)
        let rowVerticalPadding: CGFloat = 7
        #else
        let rowVerticalPadding: CGFloat = 6
        #endif

        let row = NavigationLink(value: conversation) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.app(15, weight: .regular))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if conversation.isPinned == true {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accent)
                    }
                }

                if !conversation.modelName.isEmpty {
                    Text(conversation.modelName.uppercased())
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
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                togglePin(conversation)
            } label: {
                Label(conversation.isPinned == true ? "Unpin" : "Pin", systemImage: conversation.isPinned == true ? "pin.slash" : "pin")
            }
            .tint(Color.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteConversation(conversation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }

        #if os(macOS)
        row
            .onHover { hovering in
                if hovering {
                    hoveredConversationID = conversation.id
                } else if hoveredConversationID == conversation.id {
                    hoveredConversationID = nil
                }
            }
            .listRowBackground(rowBackground(for: conversation))
            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        #else
        row
            .listRowBackground(Color.clear)
        #endif
    }

    private func rowBackground(for conversation: Conversation) -> Color {
        #if os(macOS)
        if selection?.id == conversation.id {
            return Color.accentSoft.opacity(0.5)
        }
        if hoveredConversationID == conversation.id {
            return Color.surface.opacity(0.8)
        }
        #endif
        return Color.clear
    }

    private func newConversation() {
        Haptic.impact()
        let conversation = Conversation(accountScopeKey: accountScopeKey)
        modelContext.insert(conversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to save new conversation."
            modelContext.delete(conversation)
            return
        }
        pendingConversation = conversation
        showModelPicker = true
    }

    private func deleteConversations(at offsets: IndexSet) {
        let visible = filteredConversations
        for index in offsets {
            guard index < visible.count else { continue }
            let conversation = visible[index]
            if selection?.id == conversation.id { selection = nil }
            modelContext.delete(conversation)
        }
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete conversation."
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        if selection?.id == conversation.id { selection = nil }
        modelContext.delete(conversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to delete conversation."
        }
    }

    private func togglePin(_ conversation: Conversation) {
        conversation.isPinned = !(conversation.isPinned == true)
        conversation.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to update chat pin."
        }
    }

    private func backfillLegacyConversationScopes() {
        let legacy = conversations.filter {
            $0.accountScopeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !legacy.isEmpty else { return }

        for conversation in legacy {
            conversation.accountScopeKey = accountScopeKey
        }

        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to migrate existing chats to this account scope."
        }
    }

    private func clearSelectionIfOutOfScope() {
        guard let selected = selection else { return }
        let selectedScope = selected.accountScopeKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !selectedScope.isEmpty && selectedScope != accountScopeKey {
            selection = nil
            return
        }

        if !sortedConversations.contains(where: { $0.id == selected.id }) {
            selection = nil
        }
    }

    private func deletePendingConversationIfEmpty() {
        guard let pendingConversation else { return }
        let hasModel = !pendingConversation.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMessages = !pendingConversation.messages.isEmpty
        guard !hasModel && !hasMessages else { return }

        if selection?.id == pendingConversation.id {
            selection = nil
        }
        modelContext.delete(pendingConversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to remove empty chat."
        }
    }
}
