import Foundation

/// Built-in "make the model smarter" tools, mirroring the manticthink.com web app:
/// on-device compute (`calculator`, `run_javascript`) that is always available,
/// plus an opt-in `fetch_url` that reaches the network only when the user has
/// turned on Web access. Models discover these via Ollama tool calling.
enum AssistantToolkit {

    // MARK: - Tool names

    /// Local, on-device tools — no data leaves the device, so always advertised.
    static let computeToolNames: Set<String> = ["calculator", "run_javascript"]
    /// Network tools — advertised only when the user enables Web access.
    static let webToolNames: Set<String> = ["fetch_url"]
    static let allToolNames: Set<String> = computeToolNames.union(webToolNames)

    static func handles(_ toolName: String) -> Bool {
        allToolNames.contains(toolName)
    }

    /// Tools advertised to the model. Compute tools are always on; the web tool
    /// is included only when the user has enabled Web access in Settings.
    static func tools(webAccessEnabled: Bool) -> [ChatTool] {
        var list = [calculatorTool, runJavaScriptTool]
        if webAccessEnabled { list.append(fetchURLTool) }
        return list
    }

    // MARK: - Execution

    static func execute(
        toolName: String,
        arguments: [String: JSONValue],
        webAccessEnabled: Bool
    ) async -> (content: String, isError: Bool) {
        switch toolName {
        case "calculator":
            return await runCalculator(arguments)
        case "run_javascript":
            return await runJavaScript(arguments)
        case "fetch_url":
            guard webAccessEnabled else {
                return ("Web access is turned off. The user can enable it in Settings → Chat → Web access.", true)
            }
            return await fetchURL(arguments)
        default:
            return ("Unknown tool: \(toolName)", true)
        }
    }

    // MARK: - calculator

    private static func runCalculator(_ args: [String: JSONValue]) async -> (String, Bool) {
        let expr = (args["expression"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty else { return ("Missing required parameter: expression", true) }
        // Arithmetic only — digits, operators, parentheses, and exponent notation.
        let allowed = CharacterSet(charactersIn: "0123456789+-*/%.()eE ")
        guard expr.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return ("The calculator only accepts arithmetic (digits and + - * / % . ( ) ). Use run_javascript for anything else.", true)
        }
        let result = await CodeExecutionService.execute(code: "console.log(\(expr))", language: .javascript)
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { return (out, false) }
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return (err.isEmpty ? "(no result)" : "Error: \(err)", !err.isEmpty)
    }

    // MARK: - run_javascript

    private static func runJavaScript(_ args: [String: JSONValue]) async -> (String, Bool) {
        let code = args["code"]?.stringValue ?? ""
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("Missing required parameter: code", true)
        }
        let result = await CodeExecutionService.execute(code: code, language: .javascript)
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.timedOut {
            return (err.isEmpty ? "Execution timed out." : err, true)
        }
        if !err.isEmpty {
            return (out.isEmpty ? "Error: \(err)" : "\(out)\n\nError: \(err)", true)
        }
        return (out.isEmpty ? "(no output — print results with console.log)" : out, false)
    }

    // MARK: - fetch_url

    private static let maxFetchCharacters = 8_000

    private static func fetchURL(_ args: [String: JSONValue]) async -> (String, Bool) {
        let raw = (args["url"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return ("Invalid URL. Provide a public http(s) URL.", true)
        }
        // Block loopback / private / link-local hosts so the tool can't probe
        // the user's local network.
        if isPrivateHost(host) {
            return ("Refusing to fetch a private or local address.", true)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("text/html,application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return ("HTTP \(http.statusCode) from \(host).", true)
            }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return ("The response wasn't readable text.", true)
            }
            let stripped = strippedText(text)
            let clipped = stripped.count > maxFetchCharacters
                ? String(stripped.prefix(maxFetchCharacters)) + "\n\n[Truncated to \(maxFetchCharacters) characters]"
                : stripped
            return (clipped.isEmpty ? "(empty)" : clipped, false)
        } catch {
            return ("Failed to fetch \(host): \(error.localizedDescription)", true)
        }
    }

    private static func isPrivateHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") { return true }
        if h == "0.0.0.0" || h == "::1" { return true }
        if h.hasPrefix("127.") || h.hasPrefix("10.") || h.hasPrefix("192.168.") || h.hasPrefix("169.254.") { return true }
        // 172.16.0.0 – 172.31.255.255
        if h.hasPrefix("172.") {
            let parts = h.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }

    /// Light HTML→text: drop script/style/svg, strip tags, decode a few entities,
    /// collapse whitespace. Good enough to give the model readable page content.
    private static func strippedText(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg"] {
            s = s.replacingOccurrences(
                of: "<\(tag)[^>]*>.*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tool definitions

    private static let calculatorTool = ChatTool(function: ChatToolFunction(
        name: "calculator",
        description: "Evaluate a single arithmetic expression (digits and + - * / % . parentheses only) and return the result. For anything more complex, use run_javascript.",
        parameters: ChatToolParameters(
            required: ["expression"],
            properties: ["expression": .init(type: "string", description: "e.g. (1234*56)/7")]
        )
    ))

    private static let runJavaScriptTool = ChatTool(function: ChatToolFunction(
        name: "run_javascript",
        description: "Execute JavaScript in a secure on-device sandbox and return its console output. Use for calculations, data transforms, JSON/string work, and algorithms. Print results with console.log.",
        parameters: ChatToolParameters(
            required: ["code"],
            properties: ["code": .init(type: "string", description: "JavaScript source to run.")]
        )
    ))

    private static let fetchURLTool = ChatTool(function: ChatToolFunction(
        name: "fetch_url",
        description: "Fetch the readable text of a public http(s) URL and return it (truncated to ~8000 characters). Use to read a web page or API response.",
        parameters: ChatToolParameters(
            required: ["url"],
            properties: ["url": .init(type: "string", description: "A public http(s) URL.")]
        )
    ))
}
