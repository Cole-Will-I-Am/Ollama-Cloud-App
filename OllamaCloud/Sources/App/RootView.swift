import SwiftUI

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
            // Sync AppStorage with Keychain state
            if KeychainHelper.load(key: "api_key") == nil {
                hasAPIKey = false
            }
        }
    }
}

struct MainAppView: View {
    @State private var selectedConversation: Conversation?
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            ConversationListView(selection: $selectedConversation)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(conversation: conversation)
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select or create a conversation to start chatting.")
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
