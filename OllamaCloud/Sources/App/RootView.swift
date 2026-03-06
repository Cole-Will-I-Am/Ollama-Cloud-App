import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("hasAPIKey") private var hasAPIKey = false

    var body: some View {
        Group {
            if hasAPIKey, KeychainHelper.load(key: "api_key") != nil {
                MainAppView()
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
    @State private var selectedConversation: Conversation?
    @State private var showSettings = false
    @State private var showModelPicker = false
    @State private var pendingConversation: Conversation?

    var body: some View {
        NavigationSplitView {
            ConversationListView(selection: $selectedConversation)
                .toolbar {
                    ToolbarItem(placement: .seerTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16, weight: .ultraLight))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(conversation: conversation)
            } else {
                ZStack {
                    Color.bgPrimary.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image("SeerEmblem")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 48)
                        Text("Select a conversation")
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
                        .padding(.top, 4)
                        #endif
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        #if os(macOS)
        .sheet(isPresented: $showModelPicker, onDismiss: {
            deletePendingConversationIfEmpty()
            pendingConversation = nil
        }) {
            ModelPickerView(onSelect: { model in
                if let conv = pendingConversation {
                    conv.modelName = model.name
                    try? modelContext.save()
                    selectedConversation = conv
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
        #endif
    }

    #if os(macOS)
    private func newConversationFromDetail() {
        let conversation = Conversation(accountScopeKey: AccountScope.currentKey())
        modelContext.insert(conversation)
        try? modelContext.save()
        pendingConversation = conversation
        showModelPicker = true
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
        try? modelContext.save()
    }
    #endif
}
