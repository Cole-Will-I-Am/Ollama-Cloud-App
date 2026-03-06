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
            // If the on-disk store cannot be opened (schema drift/corruption),
            // fail open with an in-memory container so the app still launches.
            print("Failed to create persistent model container, falling back to in-memory store: \(error)")
            do {
                let fallback = ModelConfiguration("OllamaCloud-Recovery", schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Failed to create fallback in-memory model container: \(error)")
            }
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
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 500)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        #endif
        .modelContainer(AppModelContainer.shared)
    }
}
