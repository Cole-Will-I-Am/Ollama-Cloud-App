#if os(macOS)
import Foundation
import MCP
import System
import OSLog

private let logger = Logger(subsystem: "com.colecantcode.ollamacloud", category: "MCP")

// MARK: - Types

struct AggregatedTool: Identifiable, Sendable {
    let serverName: String
    let tool: Tool
    var id: String { "\(serverName)::\(tool.name)" }
}

enum MCPServerState: Sendable {
    case disconnected
    case connecting
    case connected(toolCount: Int)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusLabel: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let count): return "\(count) tools"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - MCPClientManager

@MainActor
class MCPClientManager: ObservableObject {
    @Published var servers: [String: MCPServerState] = [:]
    @Published var allTools: [AggregatedTool] = []
    @Published var isLoaded = false

    private var clients: [String: Client] = [:]
    private var processes: [String: Process] = [:]
    private var serverTools: [String: [Tool]] = [:]
    private var toolToServer: [String: String] = [:]
    private var config: MCPConfig?

    private static let toolCallTimeout: TimeInterval = 30

    // MARK: - Lifecycle

    func loadAndConnect() async {
        guard !isLoaded else { return }
        isLoaded = true

        guard let config = MCPConfigLoader.load() else {
            logger.info("No MCP config found at \(MCPConfigLoader.configURL.path)")
            return
        }
        self.config = config

        for (name, serverConfig) in config.mcpServers {
            servers[name] = .connecting
            await connectServer(name: name, config: serverConfig)
        }
    }

    func shutdown() async {
        for (name, _) in clients {
            await disconnectServer(name: name)
        }
        clients.removeAll()
        processes.removeAll()
        serverTools.removeAll()
        toolToServer.removeAll()
        allTools.removeAll()
    }

    func restartServer(name: String) async {
        await disconnectServer(name: name)
        guard let serverConfig = config?.mcpServers[name] else { return }
        servers[name] = .connecting
        await connectServer(name: name, config: serverConfig)
    }

    // MARK: - Server Connection

    private func connectServer(name: String, config: MCPServerConfig) async {
        let resolvedCommand = resolveCommand(config.command)
        guard let resolvedCommand else {
            servers[name] = .error("Command not found: \(config.command)")
            logger.error("MCP server '\(name)': command not found: \(config.command)")
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: resolvedCommand)
        process.arguments = config.args ?? []
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var env = ProcessInfo.processInfo.environment
        if let extra = config.env {
            for (k, v) in extra { env[k] = v }
        }
        env["PATH"] = Self.enrichedPath(env["PATH"])
        process.environment = env

        do {
            try process.run()
        } catch {
            servers[name] = .error("Failed to launch: \(error.localizedDescription)")
            logger.error("MCP server '\(name)': launch failed: \(error.localizedDescription)")
            return
        }

        processes[name] = process

        // Drain stderr in background to prevent pipe deadlock
        let serverName = name
        Task.detached(priority: .utility) {
            let handle = stderrPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let line = String(data: data, encoding: .utf8) {
                    logger.debug("MCP stderr [\(serverName)]: \(line)")
                }
            }
        }

        // Build transport from pipe file descriptors
        // Server stdout -> our input, our output -> server stdin
        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let transport = StdioTransport(input: inputFD, output: outputFD)

        let client = Client(name: "SEER", version: "1.0")

        do {
            try await client.connect(transport: transport)
            let (tools, _) = try await client.listTools()
            clients[name] = client
            serverTools[name] = tools
            servers[name] = .connected(toolCount: tools.count)
            rebuildAggregatedTools()
            logger.info("MCP server '\(name)': connected with \(tools.count) tools")
        } catch {
            servers[name] = .error(error.localizedDescription)
            logger.error("MCP server '\(name)': connection failed: \(error.localizedDescription)")
            process.terminate()
            processes.removeValue(forKey: name)
        }
    }

    private func disconnectServer(name: String) async {
        if let client = clients[name] {
            await client.disconnect()
            clients.removeValue(forKey: name)
        }
        if let process = processes[name] {
            if process.isRunning { process.terminate() }
            processes.removeValue(forKey: name)
        }
        serverTools.removeValue(forKey: name)
        servers[name] = .disconnected
        rebuildAggregatedTools()
    }

    // MARK: - Tool Execution

    func callTool(serverName: String, toolName: String, arguments: [String: JSONValue]) async -> (content: String, isError: Bool) {
        guard let client = clients[serverName] else {
            return ("MCP server '\(serverName)' is not connected.", true)
        }

        let mcpArgs = arguments.mapValues { $0.toMCPValue() }

        do {
            let result: (content: [Tool.Content], isError: Bool?) = try await withTimeout(seconds: Self.toolCallTimeout) {
                try await client.callTool(name: toolName, arguments: mcpArgs)
            }

            let textParts = result.content.compactMap { content -> String? in
                switch content {
                case .text(let text): return text
                default: return nil
                }
            }
            let text = textParts.joined(separator: "\n")
            return (text.isEmpty ? "(no output)" : text, result.isError ?? false)
        } catch {
            let message: String
            if error is TimeoutError {
                message = "Tool execution timed out after \(Int(Self.toolCallTimeout))s"
            } else {
                message = "Tool error: \(error.localizedDescription)"
            }
            return (message, true)
        }
    }

    /// Find which server owns a given tool name.
    func serverForTool(named toolName: String) -> String? {
        toolToServer[toolName]
    }

    // MARK: - Ollama Conversion

    func ollamaTools() -> [ChatTool]? {
        guard !allTools.isEmpty else { return nil }
        return allTools.compactMap { agg in
            ollamaTool(from: agg.tool)
        }
    }

    private func ollamaTool(from tool: Tool) -> ChatTool {
        let (properties, required) = extractProperties(from: tool.inputSchema)
        let params = ChatToolParameters(required: required, properties: properties)
        let function = ChatToolFunction(
            name: tool.name,
            description: tool.description ?? "",
            parameters: params
        )
        return ChatTool(function: function)
    }

    private func extractProperties(from schema: Value) -> ([String: ChatToolProperty], [String]?) {
        guard let obj = schema.objectValue,
              let propsValue = obj["properties"],
              let propsObj = propsValue.objectValue else {
            return ([:], nil)
        }

        var properties: [String: ChatToolProperty] = [:]
        for (key, value) in propsObj {
            guard let propObj = value.objectValue else { continue }
            let type = propObj["type"]?.stringValue ?? "string"
            let desc = propObj["description"]?.stringValue ?? ""
            let enumVals: [String]? = propObj["enum"]?.arrayValue?.compactMap(\.stringValue)
            properties[key] = ChatToolProperty(type: type, description: desc, enum: enumVals)
        }

        let required = obj["required"]?.arrayValue?.compactMap(\.stringValue)
        return (properties, required)
    }

    // MARK: - Helpers

    private func rebuildAggregatedTools() {
        var tools: [AggregatedTool] = []
        var mapping: [String: String] = [:]
        for server in serverTools.keys.sorted() {
            guard let serverToolList = serverTools[server] else { continue }
            for tool in serverToolList.sorted(by: { $0.name < $1.name }) {
                if let existingServer = mapping[tool.name] {
                    logger.warning(
                        "Duplicate MCP tool name '\(tool.name)' on '\(server)'; keeping '\(existingServer)' and skipping duplicate"
                    )
                    continue
                }
                mapping[tool.name] = server
                tools.append(AggregatedTool(serverName: server, tool: tool))
            }
        }
        toolToServer = mapping
        allTools = tools
    }

    private func resolveCommand(_ command: String) -> String? {
        // If it's an absolute path, use directly
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }

        // Check known paths
        let knownDirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        for dir in knownDirs {
            let path = "\(dir)/\(command)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Login shell fallback for nvm/fnm/volta etc.
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lic", "command -v \(command) 2>/dev/null"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}
        return nil
    }

    private static func enrichedPath(_ existing: String?) -> String {
        let extra = ["/opt/homebrew/bin", "/usr/local/bin"]
        let current = existing ?? "/usr/bin:/bin"
        let parts = current.split(separator: ":").map(String.init)
        var result = parts
        for dir in extra where !parts.contains(dir) {
            result.insert(dir, at: 0)
        }
        return result.joined(separator: ":")
    }
}

// MARK: - Timeout Helper

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
#endif
