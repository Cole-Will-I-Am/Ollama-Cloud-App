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
                && conversation.isProjectChat != true
            },
            sort: \Conversation.updatedAt,
            order: .reverse
        )
    }

    private var sortedConversations: [Conversation] {
        conversations.sorted {
            let lhsPinned = $0.isPinned == true
            let rhsPinned = $1.isPinned == true
            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        List(selection: $selection) {
            #if os(macOS)
            if !conversations.isEmpty {
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
            ForEach(sortedConversations) { conversation in
                conversationRow(conversation)
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
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
        }
        .sheet(isPresented: $showModelPicker, onDismiss: {
            deletePendingConversationIfEmpty()
            pendingConversation = nil
        }) {
            ModelPickerView(onSelect: { model in
                if let conv = pendingConversation {
                    conv.modelName = model.name
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
            if conversations.isEmpty {
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
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
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

        let row = NavigationLink(value: conversation) {
            HStack(spacing: rowSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentSoft)
                        .frame(width: avatarSize, height: avatarSize)
                    Image(systemName: "cpu")
                        .font(.system(size: avatarIconSize, weight: .ultraLight))
                        .foregroundStyle(Color.accent)
                }

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
        for index in offsets {
            let conversation = sortedConversations[index]
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
