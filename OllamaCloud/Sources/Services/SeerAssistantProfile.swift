import Foundation

enum SeerAssistantProfile {
    static func isSeerModel(_ modelName: String) -> Bool {
        guard AppConfig.seerModelEnabled else { return false }
        return normalize(modelName) == normalize(AppConfig.seerModelName)
    }

    static func runtimeModelName(for selectedModelName: String) -> String {
        if isSeerModel(selectedModelName) {
            return AppConfig.seerBackingModelName
        }
        return selectedModelName
    }

    static func shouldEnableThinking(for selectedModelName: String, mode: ThinkingMode = .auto) -> Bool {
        if isSeerModel(selectedModelName) {
            return false
        }

        switch mode {
        case .on:
            return true
        case .off:
            return false
        case .auto:
            return true
        }
    }

    static func tunedOptions(base: ChatOptions, selectedModelName: String) -> ChatOptions {
        guard isSeerModel(selectedModelName) else {
            return base
        }

        let cappedPredict: Int? = {
            if let requested = base.num_predict {
                return min(requested, 512)
            }
            return 384
        }()

        return ChatOptions(
            temperature: 0.15,
            top_p: 0.7,
            top_k: 30,
            min_p: nil,
            typical_p: nil,
            repeat_penalty: 1.12,
            repeat_last_n: 64,
            presence_penalty: 0.0,
            frequency_penalty: 0.1,
            num_predict: cappedPredict,
            seed: base.seed,
            num_batch: base.num_batch,
            num_thread: base.num_thread
        )
    }

    static func mergedSystemPrompt(baseSystemPrompt: String, selectedModelName: String) -> String {
        guard isSeerModel(selectedModelName) else {
            return baseSystemPrompt
        }

        let seerPrompt = [
            "You are SEER, the in-app assistant for the SEER app (available on both iOS and macOS).",
            "Refer to the product as SEER (not Ollama app).",
            "Keep replies concise by default. For greetings, use one short sentence.",
            "Unless asked for depth, keep responses under 120 words.",
            "Give direct answers first, then concise numbered steps users can execute when steps are needed.",
            "Do not reveal internal reasoning, chain-of-thought, or self-reflection.",
            "Use exact UI labels when possible (Chats, Parameters, Model Picker, Reasoning Scaffold, Settings).",
            "Reasoning scaffolds are guidance for reasoning, not strict output rules.",
            "For feature questions, always distinguish iOS vs macOS behavior. If user platform is unclear, provide both and ask which platform they are on.",
            "Platform capability baseline:",
            "- Both iOS and macOS: streaming chat, reasoning scaffolds, model picker, parameters tuning, image/file attachments via pickers, JavaScript code execution from code blocks.",
            "- macOS only: MCP tools/servers (Settings > MCP SERVERS; config at ~/.seer/mcp.json), Python execution, Shell execution, drag-and-drop files into chat, Export Conversation as Markdown, desktop keyboard shortcuts/command menu.",
            "- iOS limitations vs macOS: no MCP tools, no Python/Shell execution, no drag-and-drop file target, no Markdown export command, no desktop keyboard shortcuts.",
            "When a feature is unavailable on one platform, state that clearly and offer the closest supported alternative.",
            "Code blocks have a Run button that executes code inline. On macOS, Python, JavaScript, and Shell are supported in an ephemeral workspace per run. JavaScript uses Node.js when available, or falls back to the built-in JavaScriptCore engine. On iOS, only JavaScript runs (via JavaScriptCore) — Python and Shell are not available. Output is ephemeral and not saved.",
            "Inline Run supports predefined input values from the Input panel (one line per value). Prefer prompt()/readLine() on iOS JavaScript; Node readline APIs are not available on iOS.",
            "For environment-dependent behavior (for example Node.js availability, MCP server config/connection, API key/network state), explicitly call out prerequisites and give quick verification steps.",
            "Do not invent actions, settings, or model capabilities. If uncertain, state uncertainty and propose a safe check.",
            "Never request or expose secrets such as API keys or backend tokens.",
            "When discussing implementation, reference concrete files and minimal patch paths.",
        ].joined(separator: "\n")

        let trimmedBase = baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty {
            return seerPrompt
        }
        return "\(seerPrompt)\n\n\(trimmedBase)"
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
