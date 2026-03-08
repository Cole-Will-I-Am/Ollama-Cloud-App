import Foundation

struct OllamaModelsResponse: Decodable {
    let models: [OllamaModel]
}

struct OllamaModel: Identifiable, Hashable {
    let name: String
    let model: String?
    let modified_at: String?
    let size: Int?
    var provider: APIProvider = .ollama

    var id: String { "\(provider.rawValue):\(name)" }

    var displayName: String {
        // Strip ":cloud" or ":latest" suffix for display
        if let idx = name.firstIndex(of: ":") {
            return String(name[..<idx])
        }
        return name
    }
}

extension OllamaModel: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, model, modified_at, size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        modified_at = try container.decodeIfPresent(String.self, forKey: .modified_at)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        provider = .ollama
    }
}
