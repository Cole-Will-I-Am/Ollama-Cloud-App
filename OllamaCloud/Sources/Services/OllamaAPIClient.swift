import Foundation

enum OllamaAPIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .unauthorized: return "Invalid API key"
        case .serverError(let msg): return msg
        case .networkError(let msg): return msg
        }
    }
}

actor OllamaAPIClient {
    static let shared = OllamaAPIClient()

    private let baseURL = "https://ollama.com"

    private var apiKey: String? {
        KeychainHelper.load(key: "api_key")
    }

    // MARK: - Validate API Key

    func validateKey(_ key: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if http.statusCode == 401 {
            return false
        }

        if http.statusCode >= 400 {
            throw OllamaAPIError.serverError("Server returned \(http.statusCode)")
        }

        return true
    }

    // MARK: - Fetch Models

    func fetchModels() async throws -> [OllamaModel] {
        guard let key = apiKey else { throw OllamaAPIError.unauthorized }
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if http.statusCode == 401 { throw OllamaAPIError.unauthorized }
        if http.statusCode >= 400 {
            throw OllamaAPIError.serverError("Failed to fetch models (\(http.statusCode))")
        }

        let decoded = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return decoded.models
    }

    // MARK: - Stream Chat

    func streamChat(
        model: String,
        messages: [ChatRequestMessage],
        options: ChatOptions? = nil
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard let key = apiKey else { throw OllamaAPIError.unauthorized }
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaAPIError.invalidResponse
        }

        let body = ChatRequest(model: model, messages: messages, stream: true, options: options)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if http.statusCode == 401 { throw OllamaAPIError.unauthorized }
        if http.statusCode >= 400 {
            // Try to read the error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                break // Just read first line
            }
            throw OllamaAPIError.serverError("Chat failed (\(http.statusCode)): \(errorBody)")
        }

        return (bytes, response)
    }
}
