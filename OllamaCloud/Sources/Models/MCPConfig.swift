#if os(macOS)
import Foundation

/// Configuration for MCP servers, read from ~/.seer/mcp.json.
/// Same format as Claude Desktop's config.
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
#endif
