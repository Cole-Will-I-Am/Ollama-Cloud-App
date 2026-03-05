import SwiftUI
import SwiftData

private enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self,
            ReasoningScaffold.self
        ])

        do {
            let configuration = ModelConfiguration("OllamaCloud", schema: schema)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create persistent model container: \(error)")
        }
    }()
}

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
        .modelContainer(AppModelContainer.shared)
    }
}
