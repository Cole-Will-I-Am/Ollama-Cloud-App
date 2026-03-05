import Foundation

struct ChatStreamChunk: Decodable {
    let model: String?
    let message: ChunkMessage?
    let done: Bool

    struct ChunkMessage: Decodable {
        let role: String
        let content: String
        let thinking: String?
    }
}
