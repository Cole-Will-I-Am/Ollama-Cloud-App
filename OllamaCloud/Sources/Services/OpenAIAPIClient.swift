import Foundation

actor OpenAIAPIClient {
    static let shared = OpenAIAPIClient()

    private let baseURL = "https://api.openai.com"
    private let modelCacheTTL: TimeInterval = 60
    private var cachedModels: [OllamaModel]?
    private var cachedModelsAt: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private let streamingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private var apiKey: String? {
        KeychainHelper.load(key: "openai_api_key")
    }

    private func makeURL(path: String) -> URL? {
        URL(string: "\(baseURL)\(path)")
    }

    private func applyAuthHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func mapError(_ error: Error, response: URLResponse? = nil) -> OllamaAPIError {
        if let apiError = error as? OllamaAPIError { return apiError }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timeout
            case .cancelled:
                return .networkError("Request cancelled")
            default:
                return .networkError(urlError.localizedDescription)
            }
        }
        if error is DecodingError { return .invalidResponse }
        return .networkError(error.localizedDescription)
    }

    private func classifyHTTPResponse(_ http: HTTPURLResponse) -> OllamaAPIError? {
        switch http.statusCode {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serverError("OpenAI server error (\(http.statusCode))")
        default:
            return .serverError("OpenAI request failed (\(http.statusCode))")
        }
    }

    // MARK: - Validate API Key

    func validateKey(_ key: String) async throws -> Bool {
        guard let url = makeURL(path: "/v1/models") else {
            throw OllamaAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        applyAuthHeaders(to: &request, apiKey: key)

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if http.statusCode == 401 { return false }
        if let error = classifyHTTPResponse(http) { throw error }
        return true
    }

    // MARK: - Fetch Models

    struct OpenAIModelsResponse: Decodable {
        let data: [OpenAIModelEntry]
    }

    struct OpenAIModelEntry: Decodable {
        let id: String
        let owned_by: String?
    }

    func fetchModels(useCache: Bool = true) async throws -> [OllamaModel] {
        if useCache, let cachedModels, let cachedModelsAt,
           Date().timeIntervalSince(cachedModelsAt) < modelCacheTTL {
            return cachedModels
        }

        guard let key = apiKey else {
            cachedModels = nil
            cachedModelsAt = nil
            throw OllamaAPIError.unauthorized
        }

        guard let url = makeURL(path: "/v1/models") else {
            throw OllamaAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        applyAuthHeaders(to: &request, apiKey: key)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if let error = classifyHTTPResponse(http) { throw error }

        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)

        // Filter to chat-capable models (gpt-*, o1-*, o3-*, chatgpt-*)
        let chatModels = decoded.data.filter { entry in
            let id = entry.id.lowercased()
            return id.hasPrefix("gpt-") || id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") || id.hasPrefix("chatgpt-")
        }

        let models: [OllamaModel] = chatModels.map { entry in
            var model = OllamaModel(name: entry.id, model: entry.id, modified_at: nil, size: nil)
            model.provider = .openai
            return model
        }

        cachedModels = models
        cachedModelsAt = Date()
        return models
    }

    // MARK: - Stream Chat

    func streamChat(
        model: String,
        messages: [ChatRequestMessage],
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        tools: [ChatTool]? = nil
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard let key = apiKey else { throw OllamaAPIError.unauthorized }
        guard let url = makeURL(path: "/v1/chat/completions") else {
            throw OllamaAPIError.invalidResponse
        }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]

        // Build messages array in OpenAI format
        body["messages"] = messages.map { msg -> [String: Any] in
            openAIMessageDict(msg)
        }

        if let temperature { body["temperature"] = temperature }
        if let topP { body["top_p"] = topP }
        if let maxTokens { body["max_tokens"] = maxTokens }
        if let presencePenalty { body["presence_penalty"] = presencePenalty }
        if let frequencyPenalty { body["frequency_penalty"] = frequencyPenalty }
        if let seed, seed != 0 { body["seed"] = seed }

        if let tools, !tools.isEmpty {
            let encoder = JSONEncoder()
            if let toolsData = try? encoder.encode(tools),
               let toolsJSON = try? JSONSerialization.jsonObject(with: toolsData) {
                body["tools"] = toolsJSON
            }
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request, apiKey: key)
        request.httpBody = jsonData

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await streamingSession.bytes(for: request)
        } catch {
            throw mapError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if let error = classifyHTTPResponse(http) { throw error }

        return (bytes, response)
    }

    private func openAIMessageDict(_ msg: ChatRequestMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": msg.role == "tool" ? "tool" : msg.role]

        if msg.role == "tool" {
            let resolvedToolCallID = msg.tool_call_id ?? msg.tool_name
            guard let toolCallID = resolvedToolCallID, !toolCallID.isEmpty else {
                dict["content"] = msg.content
                return dict
            }
            dict["tool_call_id"] = toolCallID
            dict["content"] = msg.content
            return dict
        }

        // If there are images, use content array format
        if let images = msg.images, !images.isEmpty {
            var contentArray: [[String: Any]] = []
            if !msg.content.isEmpty {
                contentArray.append(["type": "text", "text": msg.content])
            }
            for base64 in images {
                contentArray.append([
                    "type": "image_url",
                    "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                ])
            }
            dict["content"] = contentArray
        } else {
            dict["content"] = msg.content
        }

        return dict
    }
}
