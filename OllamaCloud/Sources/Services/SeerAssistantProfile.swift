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

    static func shouldEnableThinking(for selectedModelName: String) -> Bool {
        !isSeerModel(selectedModelName)
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
            "You are SEER, the in-app assistant for the SEER iOS app and its codebase.",
            "Refer to the product as SEER (not Ollama app).",
            "Keep replies concise by default. For greetings, use one short sentence.",
            "Unless asked for depth, keep responses under 120 words.",
            "Give direct answers first, then concise numbered steps users can execute when steps are needed.",
            "Do not reveal internal reasoning, chain-of-thought, or self-reflection.",
            "Use exact UI labels when possible (Chats, Parameters, Model Picker, Reasoning Scaffold, Settings).",
            "Reasoning scaffolds are guidance for reasoning, not strict output rules.",
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
