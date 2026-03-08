import SwiftUI
import SwiftData

private enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self,
            ReasoningScaffold.self,
            Project.self,
            ProjectFile.self
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
    #if os(macOS)
    @StateObject private var mcpManager = MCPClientManager()
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkMonitor)
                #if os(macOS)
                .environmentObject(mcpManager)
                #endif
                .preferredColorScheme(.dark)
                .tint(Color.accent)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 500)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        .commands {
            SidebarCommands()

            CommandGroup(after: .newItem) {
                Button("New Chat") {
                    AppCommand.post(AppCommand.newChat)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Project") {
                    AppCommand.post(AppCommand.newProject)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(after: .saveItem) {
                Button("Export Conversation…") {
                    AppCommand.post(AppCommand.exportConversation)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppCommand.post(AppCommand.openSettings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Chat") {
                Button("Send Message") {
                    AppCommand.post(AppCommand.sendMessage)
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Quick Model Switch") {
                    AppCommand.post(AppCommand.quickModelSwitch)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Previous Branch") {
                    AppCommand.post(AppCommand.previousBranch)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Button("Next Branch") {
                    AppCommand.post(AppCommand.nextBranch)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Divider()

                Button("Close Chat") {
                    AppCommand.post(AppCommand.closeChat)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Divider()

                Button("Conversation 1") {
                    AppCommand.postSelectConversation(index: 0)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Conversation 2") {
                    AppCommand.postSelectConversation(index: 1)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Conversation 3") {
                    AppCommand.postSelectConversation(index: 2)
                }
                .keyboardShortcut("3", modifiers: .command)
            }
        }
        #endif
        .modelContainer(AppModelContainer.shared)
    }
}
