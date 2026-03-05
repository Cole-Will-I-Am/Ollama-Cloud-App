import SwiftUI
import SwiftData

@main
struct OllamaCloudApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Color.accent)
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
