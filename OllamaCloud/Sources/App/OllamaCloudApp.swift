import SwiftUI
import SwiftData

@main
struct OllamaCloudApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
