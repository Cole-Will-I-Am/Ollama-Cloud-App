import Foundation

struct OllamaModelsResponse: Decodable {
    let models: [OllamaModel]
}

struct OllamaModel: Decodable, Identifiable, Hashable {
    let name: String
    let model: String?
    let modified_at: String?
    let size: Int?

    var id: String { name }

    var displayName: String {
        // Strip ":cloud" or ":latest" suffix for display
        if let idx = name.firstIndex(of: ":") {
            return String(name[..<idx])
        }
        return name
    }
}
