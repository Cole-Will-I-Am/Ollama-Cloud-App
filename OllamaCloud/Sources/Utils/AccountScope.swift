import Foundation
import CryptoKit

enum AccountScope {
    static func currentKey() -> String {
        let apiKey = KeychainHelper.load(key: "api_key") ?? ""
        return scopeKey(apiBaseURL: AppConfig.apiBaseURL, apiKey: apiKey)
    }

    static func scopeKey(apiBaseURL: String, apiKey: String) -> String {
        let host = URL(string: apiBaseURL)?.host?.lowercased()
            ?? apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let fingerprint = SHA256.hash(data: Data(normalizedKey.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return "\(host)#\(fingerprint)"
    }
}
