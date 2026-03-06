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
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundStyle(Color.textTertiary)
                        Text("Select a conversation")
                            .font(.app(14, weight: .light))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
