import Foundation

enum AppConfig {
    static let apiBaseURLKey = "api_base_url"
    static let backendBearerTokenKey = "backend_bearer_token"
    static let reasoningScaffoldsEnabledKey = "reasoning_scaffolds_enabled"

    private static let defaultAPIBaseURL = "https://ollama.com"

    static var apiBaseURL: String {
        let defaultsValue = UserDefaults.standard.string(forKey: apiBaseURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = defaultsValue, !value.isEmpty {
            return value
        }

        let envValue = ProcessInfo.processInfo.environment["OLLAMA_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = envValue, !value.isEmpty {
            return value
        }

        return defaultAPIBaseURL
    }

    static var backendBearerToken: String? {
        let defaultsValue = UserDefaults.standard.string(forKey: backendBearerTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = defaultsValue, !value.isEmpty {
            return value
        }

        let envValue = ProcessInfo.processInfo.environment["OLLAMA_BACKEND_BEARER_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = envValue, !value.isEmpty {
            return value
        }

        return nil
    }

    static var apiHostDisplayName: String {
        if let host = URL(string: apiBaseURL)?.host, !host.isEmpty {
            return host
        }
        return apiBaseURL
    }

    static var reasoningScaffoldsEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: reasoningScaffoldsEnabledKey) {
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let stringValue = value as? String {
                return parseBoolString(stringValue, defaultValue: true)
            }
        }

        if let envValue = ProcessInfo.processInfo.environment["REASONING_SCAFFOLDS_ENABLED"] {
            return parseBoolString(envValue, defaultValue: true)
        }

        return true
    }

    private static func parseBoolString(_ raw: String, defaultValue: Bool) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return defaultValue
        }
        if ["1", "true", "yes", "on"].contains(normalized) {
            return true
        }
        if ["0", "false", "no", "off"].contains(normalized) {
            return false
        }
        return defaultValue
    }
}
