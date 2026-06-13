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

        let configuration = ModelConfiguration("OllamaCloud", schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // The on-disk store couldn't be opened — almost always schema drift
            // across app updates (there is no migration plan). Rather than
            // silently running in-memory (which loses every chat on relaunch),
            // reset the store once and recreate a PERSISTENT container so new
            // chats actually save going forward.
            print("Persistent store failed to open (\(error)). Setting store aside and retrying.")
            setAsideStoreFiles(at: configuration.url)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // True last resort: in-memory so the app at least launches.
                print("Reset store still failed (\(error)). Falling back to in-memory.")
                do {
                    let fallback = ModelConfiguration("OllamaCloud-Recovery", schema: schema, isStoredInMemoryOnly: true)
                    return try ModelContainer(for: schema, configurations: [fallback])
                } catch {
                    fatalError("Failed to create fallback in-memory model container: \(error)")
                }
            }
        }
    }()

    /// Move the SQLite store and its WAL/SHM sidecar files aside so a fresh
    /// persistent store can be created in its place. A failed open can be
    /// transient (corrupt WAL, disk pressure) — keep the files recoverable
    /// instead of deleting the user's entire history.
    private static func setAsideStoreFiles(at url: URL) {
        let fileManager = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            guard fileManager.fileExists(atPath: path) else { continue }
            do {
                try fileManager.moveItem(atPath: path, toPath: path + ".bak-\(stamp)")
            } catch {
                // If the file can't be moved the fresh store can't be created
                // at this path — deleting is the only way forward.
                try? fileManager.removeItem(atPath: path)
            }
        }
    }
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
