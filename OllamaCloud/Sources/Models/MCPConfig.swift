#if os(macOS)
import Foundation

// MARK: - Custom server config (from ~/.seer/mcp.json)

struct MCPConfig: Codable {
    let mcpServers: [String: MCPServerConfig]
}

struct MCPServerConfig: Codable {
    let command: String
    let args: [String]?
    let env: [String: String]?
}

enum MCPConfigLoader {
    static let configURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".seer")
            .appendingPathComponent("mcp.json")
    }()

    static func load() -> MCPConfig? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }
        return try? JSONDecoder().decode(MCPConfig.self, from: data)
    }
}

// MARK: - Built-in server registry

struct BuiltInMCPServer: Identifiable {
    let id: String          // UserDefaults key suffix + display name
    let description: String
    let icon: String        // SF Symbol
    let command: String
    let args: [String]
    let env: [String: String]?
    let runtime: Runtime

    enum Runtime: String {
        case node
        case uv
    }

    var defaultsKey: String { "mcp_enabled_\(id)" }

    func toServerConfig() -> MCPServerConfig {
        MCPServerConfig(command: command, args: args, env: env)
    }

    /// Built-in servers are opt-in by default.
    static let defaultEnabled = false
}

enum BuiltInMCPRegistry {
    static let servers: [BuiltInMCPServer] = [
        BuiltInMCPServer(
            id: "Filesystem",
            description: "Read, write, and search files",
            icon: "folder",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp",
                   FileManager.default.homeDirectoryForCurrentUser.path],
            env: nil,
            runtime: .node
        ),
        BuiltInMCPServer(
            id: "Desktop Commander",
            description: "Shell, processes, and system control",
            icon: "terminal",
            command: "npx",
            args: ["-y", "@wonderwhy-er/desktop-commander"],
            env: nil,
            runtime: .node
        ),
        BuiltInMCPServer(
            id: "Mantic",
            description: "Mantic scaffold reasoning engine",
            icon: "brain.head.profile",
            command: "uv",
            args: [
                "run",
                "--project", FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("mantic-scaffold").path,
                "--with", "fastmcp",
                "--with-editable", FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("mantic-scaffold").path,
                "--with-editable", FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("mantic-thinking").path,
                "fastmcp", "run", "--transport", "stdio",
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("mantic-scaffold/mantic_scaffold/server.py:mcp").path
            ],
            env: nil,
            runtime: .uv
        )
    ]

    static func isEnabled(_ server: BuiltInMCPServer) -> Bool {
        // If the key has never been set, use the default (currently false)
        if UserDefaults.standard.object(forKey: server.defaultsKey) == nil {
            return BuiltInMCPServer.defaultEnabled
        }
        return UserDefaults.standard.bool(forKey: server.defaultsKey)
    }

    static func setEnabled(_ server: BuiltInMCPServer, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: server.defaultsKey)
    }
}

// MARK: - MCP library catalog + config install

struct MCPLibraryServer: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let icon: String
    let command: String
    let args: [String]
    let env: [String: String]?

    func toServerConfig() -> MCPServerConfig {
        MCPServerConfig(command: command, args: args, env: env)
    }
}

enum MCPLibraryRegistry {
    static let servers: [MCPLibraryServer] = [
        MCPLibraryServer(
            id: "memory",
            displayName: "Memory",
            description: "Persistent memory and note retrieval",
            icon: "brain",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-memory"],
            env: nil
        ),
        MCPLibraryServer(
            id: "sequential-thinking",
            displayName: "Sequential Thinking",
            description: "Structured multi-step reasoning toolset",
            icon: "list.number",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-sequential-thinking"],
            env: nil
        ),
        MCPLibraryServer(
            id: "github",
            displayName: "GitHub",
            description: "Repo and issue operations via GitHub API",
            icon: "chevron.left.forwardslash.chevron.right",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"],
            env: ["GITHUB_PERSONAL_ACCESS_TOKEN": "REPLACE_WITH_TOKEN"]
        ),
        MCPLibraryServer(
            id: "brave-search",
            displayName: "Brave Search",
            description: "Web search with Brave API",
            icon: "magnifyingglass",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-brave-search"],
            env: ["BRAVE_API_KEY": "REPLACE_WITH_KEY"]
        ),
        MCPLibraryServer(
            id: "postgres",
            displayName: "Postgres",
            description: "Query and inspect PostgreSQL databases",
            icon: "cylinder",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-postgres"],
            env: ["POSTGRES_CONNECTION_STRING": "postgresql://user:pass@host:5432/db"]
        ),
        MCPLibraryServer(
            id: "puppeteer",
            displayName: "Puppeteer",
            description: "Browser automation and page interaction",
            icon: "safari",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-puppeteer"],
            env: nil
        )
    ]
}

enum MCPConfigStoreError: LocalizedError {
    case invalidServerName
    case alreadyInstalled(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerName:
            return "Invalid MCP server name."
        case .alreadyInstalled(let name):
            return "'\(name)' is already installed in ~/.seer/mcp.json."
        }
    }
}

enum MCPConfigStore {
    static func installedServerNames() -> Set<String> {
        guard let config = MCPConfigLoader.load() else { return [] }
        return Set(config.mcpServers.keys)
    }

    static func installLibraryServer(_ server: MCPLibraryServer) throws {
        try upsertServer(name: server.id, config: server.toServerConfig(), overwrite: false)
    }

    static func upsertServer(name: String, config: MCPServerConfig, overwrite: Bool) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MCPConfigStoreError.invalidServerName
        }

        var servers = MCPConfigLoader.load()?.mcpServers ?? [:]
        if servers[trimmed] != nil && !overwrite {
            throw MCPConfigStoreError.alreadyInstalled(trimmed)
        }
        servers[trimmed] = config

        let directoryURL = MCPConfigLoader.configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(MCPConfig(mcpServers: servers))
        try data.write(to: MCPConfigLoader.configURL, options: .atomic)
    }
}
#endif
