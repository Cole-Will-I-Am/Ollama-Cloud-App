import Foundation

enum APIProvider: String, Codable, CaseIterable {
    case ollama
    case openai

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openai: return "OpenAI"
        }
    }
}
