import Foundation
import CryptoKit

// MARK: - Error Types

enum OllamaAPIError: LocalizedError {
    case offline
    case timeout
    case unauthorized
    case modelUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(String)
    case invalidResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .offline: return "No internet connection"
        case .timeout: return "Request timed out"
        case .unauthorized: return "Invalid API key"
        case .modelUnavailable: return "Selected model is unavailable"
        case .rateLimited: return "Too many requests — please wait a moment"
        case .serverError(let msg): return msg
        case .invalidResponse: return "Invalid server response"
        case .networkError(let msg): return msg
        }
    }

    /// User-friendly short string for display in error bubbles
    var userMessage: String {
        switch self {
        case .offline: return "You're offline. Check your connection."
        case .timeout: return "Request timed out. Try again."
        case .unauthorized: return "Invalid API key. Remove it in Settings and re-enter."
        case .modelUnavailable: return "Selected model is no longer available. Choose another model."
        case .rateLimited: return "Rate limited. Wait a moment and retry."
        case .serverError: return "Server error. Try again shortly."
        case .invalidResponse: return "Unexpected response from server."
        case .networkError: return "Network error. Check your connection."
        }
    }

    var isTransient: Bool {
        switch self {
        case .timeout, .serverError, .networkError, .offline: return true
        case .unauthorized, .modelUnavailable, .rateLimited, .invalidResponse: return false
        }
    }

    var suggestsModelReselect: Bool {
        switch self {
        case .modelUnavailable:
            return true
        default:
            return false
        }
    }
}

// MARK: - Pinning Delegate

private final class PinningDelegate: NSObject, URLSessionDelegate, Sendable {
    // SHA-256 hashes of raw public key bytes for ollama.com's certificate chain.
    // Note: these are not SPKI DER hashes.
    // Leave empty to use standard TLS validation until real pins are configured.
    private let pinnedHashes: Set<String> = [
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              challenge.protectionSpace.host.hasSuffix("ollama.com") else {
            return (.performDefaultHandling, nil)
        }

        // If pins are not configured yet, rely on platform trust evaluation.
        guard !pinnedHashes.isEmpty else {
            return (.performDefaultHandling, nil)
        }

        // Evaluate the trust chain
        var cfError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &cfError) else {
            return (.cancelAuthenticationChallenge, nil)
        }

        // Check each certificate in the chain for a matching public-key hash
        guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return (.cancelAuthenticationChallenge, nil)
        }
        for cert in certChain {
            let publicKeyData = SecCertificateCopyKey(cert).flatMap { key in
                SecKeyCopyExternalRepresentation(key, nil) as Data?
            }
            if let data = publicKeyData {
                let hash = "sha256/" + Data(SHA256.hash(data: data)).base64EncodedString()
                if pinnedHashes.contains(hash) {
                    return (.useCredential, URLCredential(trust: serverTrust))
                }
            }
        }

        // No pin matched — reject
        return (.cancelAuthenticationChallenge, nil)
    }
}

// MARK: - API Client

actor OllamaAPIClient {
    static let shared = OllamaAPIClient()

    private let maxRetries = 2
    private let retryDelays: [UInt64] = [1_000_000_000, 3_000_000_000] // 1s, 3s in nanoseconds
    private let modelCacheTTL: TimeInterval = 60
    private var cachedModels: [OllamaModel]?
    private var cachedModelsAt: Date?
    private var cachedModelsScopeKey: String?

    // Dedicated session with timeouts
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30     // 30s per request
        config.timeoutIntervalForResource = 300   // 5min for streaming
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: PinningDelegate(), delegateQueue: nil)
    }()

    // Longer timeout session for streaming
    private let streamingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60     // 60s between chunks
        config.timeoutIntervalForResource = 600   // 10min total for long generations
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: PinningDelegate(), delegateQueue: nil)
    }()

    private var apiKey: String? {
        KeychainHelper.load(key: "api_key")
    }

    private var baseURL: String {
        AppConfig.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func cacheScopeKey(for key: String?) -> String? {
        guard let key, !key.isEmpty else { return nil }
        let host = URL(string: baseURL)?.host?.lowercased() ?? baseURL.lowercased()
        let digest = SHA256.hash(data: Data(key.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return "\(host)#\(digest)"
    }

    private func makeURL(path: String) -> URL? {
        URL(string: "\(baseURL)\(path)")
    }

    private func applyAuthHeaders(to request: inout URLRequest, userAPIKey: String) {
        if let backendToken = AppConfig.backendBearerToken {
            request.setValue("Bearer \(backendToken)", forHTTPHeaderField: "Authorization")
            request.setValue(userAPIKey, forHTTPHeaderField: "X-Ollama-Key")
        } else {
            request.setValue("Bearer \(userAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue(nil, forHTTPHeaderField: "X-Ollama-Key")
        }
    }

    // MARK: - Error Mapping

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
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return .networkError("Certificate validation failed")
            default:
                return .networkError(urlError.localizedDescription)
            }
        }

        if error is DecodingError {
            return .invalidResponse
        }

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
            return .serverError("Server error (\(http.statusCode))")
        default:
            return .serverError("Request failed (\(http.statusCode))")
        }
    }

    // MARK: - Retry Logic

    private func performWithRetry<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                let mapped = mapError(error)
                guard mapped.isTransient, attempt < maxRetries else { throw mapped }
                lastError = mapped
                try await Task.sleep(nanoseconds: retryDelays[attempt])
            }
        }
        throw lastError ?? OllamaAPIError.networkError("Unknown error")
    }

    // MARK: - Validate API Key

    func validateKey(_ key: String) async throws -> Bool {
        try await performWithRetry {
            guard let url = self.makeURL(path: "/api/tags") else {
                throw OllamaAPIError.invalidResponse
            }

            var request = URLRequest(url: url)
            self.applyAuthHeaders(to: &request, userAPIKey: key)

            let (_, response) = try await self.session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw OllamaAPIError.invalidResponse
            }

            if http.statusCode == 401 { return false }

            if let error = self.classifyHTTPResponse(http) { throw error }
            return true
        }
    }

    // MARK: - Fetch Models

    func fetchModels(useCache: Bool = true) async throws -> [OllamaModel] {
        let key = apiKey
        let scopeKey = cacheScopeKey(for: key)

        if useCache,
           let cachedModels,
           let cachedModelsAt,
           let cachedModelsScopeKey,
           cachedModelsScopeKey == scopeKey,
           Date().timeIntervalSince(cachedModelsAt) < modelCacheTTL {
            return cachedModels
        }

        return try await performWithRetry {
            guard let key else {
                self.cachedModels = nil
                self.cachedModelsAt = nil
                self.cachedModelsScopeKey = nil
                throw OllamaAPIError.unauthorized
            }
            guard let url = self.makeURL(path: "/api/tags") else {
                throw OllamaAPIError.invalidResponse
            }

            var request = URLRequest(url: url)
            self.applyAuthHeaders(to: &request, userAPIKey: key)

            let (data, response) = try await self.session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw OllamaAPIError.invalidResponse
            }

            if let error = self.classifyHTTPResponse(http) { throw error }

            let decoded = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
            let models = self.injectSeerModel(into: decoded.models)
            self.cachedModels = models
            self.cachedModelsAt = Date()
            self.cachedModelsScopeKey = scopeKey
            return models
        }
    }

    func isModelAvailable(_ modelName: String) async throws -> Bool {
        let normalizedModel = normalizeModelName(modelName)
        let cached = try await fetchModels(useCache: true)
        if containsModel(named: normalizedModel, in: cached) {
            return true
        }

        let fresh = try await fetchModels(useCache: false)
        return containsModel(named: normalizedModel, in: fresh)
    }

    private func containsModel(named modelName: String, in models: [OllamaModel]) -> Bool {
        let normalizedTarget = normalizeModelName(modelName)
        for model in models {
            if normalizeModelName(model.name) == normalizedTarget {
                return true
            }
        }
        return false
    }

    private func normalizeModelName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func injectSeerModel(into models: [OllamaModel]) -> [OllamaModel] {
        guard AppConfig.seerModelEnabled else { return models }
        let seerName = AppConfig.seerModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !seerName.isEmpty else { return models }

        let normalizedSeer = normalizeModelName(seerName)
        if models.contains(where: { normalizeModelName($0.name) == normalizedSeer }) {
            return models
        }

        var updated = models
        updated.append(OllamaModel(name: seerName, model: seerName, modified_at: nil, size: nil))
        return updated
    }

    // MARK: - Stream Chat (no retry — caller handles retry for streams)

    func streamChat(
        model: String,
        messages: [ChatRequestMessage],
        think: Bool = true,
        options: ChatOptions? = nil
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard let key = apiKey else { throw OllamaAPIError.unauthorized }
        guard let url = makeURL(path: "/api/chat") else {
            throw OllamaAPIError.invalidResponse
        }

        let body = ChatRequest(
            model: model,
            messages: messages,
            stream: true,
            think: think,
            options: options
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request, userAPIKey: key)
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await streamingSession.bytes(for: request)
        } catch {
            throw mapError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OllamaAPIError.invalidResponse
        }

        if http.statusCode == 400 || http.statusCode == 404 {
            throw OllamaAPIError.modelUnavailable
        }

        if let error = classifyHTTPResponse(http) {
            // Try to read error body for server errors
            if case .serverError = error {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                    break
                }
                if !errorBody.isEmpty {
                    throw OllamaAPIError.serverError("Chat failed (\(http.statusCode)): \(errorBody)")
                }
            }
            throw error
        }

        return (bytes, response)
    }
}
