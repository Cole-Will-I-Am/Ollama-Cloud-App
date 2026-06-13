import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasAPIKey") private var hasAPIKey = false
    @AppStorage(ConsentStore.storageKey) private var consentSignature = ""

    var body: some View {
        Group {
            if hasAPIKey, KeychainHelper.load(key: "api_key") != nil {
                if ConsentStore.hasConsented(signature: consentSignature) {
                    MainAppView()
                } else {
                    DataSharingConsentView()
                }
            } else {
                APIKeyEntryView()
            }
        }
        .onAppear {
            if KeychainHelper.load(key: "api_key") == nil {
                hasAPIKey = false
            }
        }
    }
}

struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    #if os(macOS)
    @EnvironmentObject private var mcpManager: MCPClientManager
    @AppStorage("mcpEnabled") private var mcpEnabled = false
    #endif
    private let accountScopeKey: String
    @Query private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?
    @State private var showSettings = false
    @State private var persistenceError: String?
    @State private var showModelPicker = false
    @State private var pendingConversation: Conversation?

    init(accountScopeKey: String = AccountScope.currentKey()) {
        self.accountScopeKey = accountScopeKey
        _conversations = Query(
            filter: #Predicate<Conversation> { conversation in
                (conversation.accountScopeKey == accountScopeKey
                 || conversation.accountScopeKey == "")
                // isProjectChat is nil for normal chats; SwiftData's SQLite
                // translation of `!= true` drops NULL rows, so match nil/false
                // explicitly (otherwise normal chats vanish from the list).
                && (conversation.isProjectChat == nil || conversation.isProjectChat == false)
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
        NavigationSplitView {
            ConversationListView(selection: $selectedConversation)
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 360)
            #endif
            .toolbar {
                ToolbarItem(placement: .seerTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .ultraLight))
                            .foregroundStyle(Color.textSecondary)
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    .macPointingCursor()
                    #endif
                }
            }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(conversation: conversation)
            } else {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()
                    VStack(spacing: 14) {
                        #if os(macOS)
                        Image("SeerEmblem")
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 48)
                        #else
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        #endif
                        Text("Let's Party.")
                            .font(.app(14, weight: .light))
                            .foregroundStyle(Color.textTertiary)
                        #if os(macOS)
                        Button {
                            newConversationFromDetail()
                        } label: {
                            Text("+ NEW CHAT")
                                .font(.appLabel(11))
                                .luxuryTracking()
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.accentSoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .macPointingCursor()
                        .padding(.top, 4)
                        #endif
                    }
                }
            }
        }
        #if os(macOS)
        .background(Color.bgPrimary.ignoresSafeArea())
        .task {
            if mcpEnabled {
                await mcpManager.loadAndConnect()
            }
        }
        #endif
        .sheet(isPresented: $showSettings) {
            SettingsView()
                #if os(macOS)
                .presentationBackground(Color.bgPrimary)
                #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.openSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.dataReset)) { _ in
            selectedConversation = nil
        }
        .alert("Storage Error", isPresented: Binding(
            get: { persistenceError != nil },
            set: { _ in persistenceError = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "An unknown storage error occurred.")
        }
        #if os(macOS)
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
                    } catch {
                        persistenceError = "Failed to save model selection."
                        return
                    }
                    selectedConversation = conv
                }
                pendingConversation = nil
                showModelPicker = false
            }, onCancel: {
                deletePendingConversationIfEmpty()
                pendingConversation = nil
                showModelPicker = false
            })
            .presentationBackground(Color.bgPrimary)
            .macSheetFixedSize(SeerSheetSize.modelPicker)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.newChat)) { _ in
            newConversationFromDetail()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.closeChat)) { _ in
            selectedConversation = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: AppCommand.selectConversationIndex)) { notification in
            guard let index = AppCommand.conversationIndex(from: notification) else { return }
            selectConversation(at: index)
        }
        #endif
    }

    #if os(macOS)
    private func newConversationFromDetail() {
        guard !showModelPicker else { return }
        let conversation = Conversation(accountScopeKey: AccountScope.currentKey())
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

    private func selectConversation(at index: Int) {
        guard index >= 0, index < sortedConversations.count else { return }
        selectedConversation = sortedConversations[index]
    }

    private func deletePendingConversationIfEmpty() {
        guard let pendingConversation else { return }
        let hasModel = !pendingConversation.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMessages = !pendingConversation.messages.isEmpty
        guard !hasModel && !hasMessages else { return }
        if selectedConversation?.id == pendingConversation.id {
            selectedConversation = nil
        }
        modelContext.delete(pendingConversation)
        do {
            try modelContext.save()
        } catch {
            persistenceError = "Failed to remove empty chat."
        }
    }

    #endif

}
