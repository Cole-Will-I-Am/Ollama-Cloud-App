import Foundation

enum AppConfig {
    static let apiBaseURLKey = "api_base_url"
    static let backendBearerTokenKey = "backend_bearer_token"

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
}
