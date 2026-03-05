import SwiftUI
import SwiftData

@main
struct OllamaCloudApp: App {
    @StateObject private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkMonitor)
                .preferredColorScheme(.dark)
                .tint(Color.accent)
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
