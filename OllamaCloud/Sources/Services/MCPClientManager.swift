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
    @Published var connectingStartedAt: [String: Date] = [:]
    @Published var allTools: [AggregatedTool] = []
    @Published var isLoaded = false

    private var clients: [String: Client] = [:]
    private var processes: [String: Process] = [:]
    private var serverTools: [String: [Tool]] = [:]
    private var toolToServer: [String: String] = [:]
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    private var serverGenerations: [String: Int] = [:]
    private var config: MCPConfig?

    private static let toolCallTimeout: TimeInterval = 30
    private static let connectionTimeout: TimeInterval = 90
    private static let verboseServerLogs = ProcessInfo.processInfo.environment["SEER_MCP_STDERR_LOG"] == "1"
    private static let stderrLogWindow: TimeInterval = 10
    private static let stderrLogBurst = 5

    // MARK: - Lifecycle

    func loadAndConnect() async {
        guard !isLoaded else { return }
        isLoaded = true

        // Load built-in servers (respecting toggles)
        for builtIn in BuiltInMCPRegistry.servers {
            guard BuiltInMCPRegistry.isEnabled(builtIn) else {
                _ = bumpGeneration(for: builtIn.id)
                servers[builtIn.id] = .disconnected
                continue
            }
            servers[builtIn.id] = .connecting
            let generation = bumpGeneration(for: builtIn.id)
            startConnection(name: builtIn.id, config: builtIn.toServerConfig(), generation: generation)
        }

        // Load custom servers from ~/.seer/mcp.json
        if let config = MCPConfigLoader.load() {
            self.config = config
            let builtInIDs = Set(BuiltInMCPRegistry.servers.map(\.id))
            for (name, serverConfig) in config.mcpServers where !builtInIDs.contains(name) {
                guard CustomMCPRegistry.isEnabled(serverName: name) else {
                    _ = bumpGeneration(for: name)
                    servers[name] = .disconnected
                    continue
                }
                servers[name] = .connecting
                let generation = bumpGeneration(for: name)
                startConnection(name: name, config: serverConfig, generation: generation)
            }
        }
    }

    func shutdown() async {
        let activeNames = Set(clients.keys)
            .union(processes.keys)
            .union(connectionTasks.keys)
            .union(connectingStartedAt.keys)
        for name in activeNames {
            _ = bumpGeneration(for: name)
            await disconnectServer(name: name)
        }
        clients.removeAll()
        processes.removeAll()
        serverTools.removeAll()
        toolToServer.removeAll()
        connectionTasks.values.forEach { $0.cancel() }
        connectionTasks.removeAll()
        servers.removeAll()
        connectingStartedAt.removeAll()
        allTools.removeAll()
        isLoaded = false
    }

    func restartServer(name: String) async {
        let generation = bumpGeneration(for: name)
        await disconnectServer(name: name)

        // Check built-in first, then custom config
        if let builtIn = BuiltInMCPRegistry.servers.first(where: { $0.id == name }) {
            servers[name] = .connecting
            startConnection(name: name, config: builtIn.toServerConfig(), generation: generation)
        } else if let serverConfig = config?.mcpServers[name] {
            guard CustomMCPRegistry.isEnabled(serverName: name) else {
                servers[name] = .disconnected
                return
            }
            servers[name] = .connecting
            startConnection(name: name, config: serverConfig, generation: generation)
        }
    }

    /// Toggle a built-in server on or off. Connects or disconnects immediately.
    func toggleBuiltInServer(_ server: BuiltInMCPServer, enabled: Bool) async {
        BuiltInMCPRegistry.setEnabled(server, enabled: enabled)
        if enabled {
            let generation = bumpGeneration(for: server.id)
            servers[server.id] = .connecting
            startConnection(name: server.id, config: server.toServerConfig(), generation: generation)
        } else {
            _ = bumpGeneration(for: server.id)
            await disconnectServer(name: server.id)
        }
    }

    /// Toggle a custom server (from ~/.seer/mcp.json) on or off.
    func toggleCustomServer(name: String, enabled: Bool) async {
        CustomMCPRegistry.setEnabled(serverName: name, enabled: enabled)
        if enabled {
            if config == nil {
                config = MCPConfigLoader.load()
            }
            guard let serverConfig = config?.mcpServers[name] else {
                servers[name] = .error("Missing config for '\(name)' in ~/.seer/mcp.json")
                return
            }
            let generation = bumpGeneration(for: name)
            servers[name] = .connecting
            startConnection(name: name, config: serverConfig, generation: generation)
        } else {
            _ = bumpGeneration(for: name)
            await disconnectServer(name: name)
        }
    }

    // MARK: - Server Connection

    private func startConnection(name: String, config: MCPServerConfig, generation: Int) {
        connectionTasks[name]?.cancel()
        connectionTasks[name] = Task { [weak self] in
            await self?.connectServer(name: name, config: config, generation: generation)
        }
    }

    private func connectServer(name: String, config: MCPServerConfig, generation: Int) async {
        guard isCurrent(generation, for: name) else { return }
        let resolvedCommand = resolveCommand(config.command)
        guard let resolvedCommand else {
            if isCurrent(generation, for: name) {
                servers[name] = .error("Command not found: \(config.command)")
                connectingStartedAt.removeValue(forKey: name)
                logger.error("MCP server '\(name)': command not found: \(config.command)")
                connectionTasks.removeValue(forKey: name)
            }
            return
        }

        guard !Task.isCancelled, isCurrent(generation, for: name) else { return }

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
            if isCurrent(generation, for: name) {
                servers[name] = .error("Failed to launch: \(error.localizedDescription)")
                connectingStartedAt.removeValue(forKey: name)
                logger.error("MCP server '\(name)': launch failed: \(error.localizedDescription)")
                connectionTasks.removeValue(forKey: name)
            }
            return
        }

        processes[name] = process

        // Drain stderr in background to prevent pipe deadlock
        let serverName = name
        Task.detached(priority: .utility) {
            let handle = stderrPipe.fileHandleForReading
            var windowStart = Date()
            var emitted = 0
            var suppressed = 0
            while true {
                let data = handle.availableData
                if data.isEmpty { break }

                // Keep draining regardless, but only emit logs when explicitly enabled.
                guard Self.verboseServerLogs else { continue }

                if Date().timeIntervalSince(windowStart) >= Self.stderrLogWindow {
                    if suppressed > 0 {
                        logger.debug("MCP stderr [\(serverName)]: suppressed \(suppressed) log chunks in last \(Int(Self.stderrLogWindow))s")
                    }
                    windowStart = Date()
                    emitted = 0
                    suppressed = 0
                }

                if emitted < Self.stderrLogBurst {
                    if let line = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines),
                       !line.isEmpty {
                        logger.debug("MCP stderr [\(serverName)]: \(line)")
                        emitted += 1
                    }
                } else {
                    suppressed += 1
                }
            }
            if Self.verboseServerLogs, suppressed > 0 {
                logger.debug("MCP stderr [\(serverName)]: suppressed \(suppressed) additional log chunks")
            }
        }

        // Build transport from pipe file descriptors
        // Server stdout -> our input, our output -> server stdin
        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let transport = StdioTransport(input: inputFD, output: outputFD)

        let client = Client(name: "SEER", version: "1.0")
        connectingStartedAt[name] = Date()

        do {
            let (tools, _): ([Tool], String?) = try await withTimeout(seconds: Self.connectionTimeout) {
                try await client.connect(transport: transport)
                return try await client.listTools()
            }
            guard !Task.isCancelled, isCurrent(generation, for: name) else {
                await client.disconnect()
                if process.isRunning { process.terminate() }
                processes.removeValue(forKey: name)
                return
            }
            clients[name] = client
            serverTools[name] = tools
            servers[name] = .connected(toolCount: tools.count)
            connectingStartedAt.removeValue(forKey: name)
            connectionTasks.removeValue(forKey: name)
            rebuildAggregatedTools()
            logger.info("MCP server '\(name)': connected with \(tools.count) tools")
        } catch {
            guard isCurrent(generation, for: name) else {
                if process.isRunning { process.terminate() }
                processes.removeValue(forKey: name)
                return
            }
            connectingStartedAt.removeValue(forKey: name)
            let message = error is TimeoutError
                ? "Connection timed out (\(Int(Self.connectionTimeout))s)"
                : error.localizedDescription
            servers[name] = .error(message)
            logger.error("MCP server '\(name)': connection failed: \(message)")
            process.terminate()
            processes.removeValue(forKey: name)
            connectionTasks.removeValue(forKey: name)
        }
    }

    private func disconnectServer(name: String) async {
        if let task = connectionTasks[name] {
            task.cancel()
            connectionTasks.removeValue(forKey: name)
        }
        if let client = clients[name] {
            await client.disconnect()
            clients.removeValue(forKey: name)
        }
        if let process = processes[name] {
            if process.isRunning { process.terminate() }
            processes.removeValue(forKey: name)
        }
        serverTools.removeValue(forKey: name)
        connectingStartedAt.removeValue(forKey: name)
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

    private func bumpGeneration(for name: String) -> Int {
        let next = (serverGenerations[name] ?? 0) + 1
        serverGenerations[name] = next
        return next
    }

    private func isCurrent(_ generation: Int, for name: String) -> Bool {
        serverGenerations[name] == generation
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
