import Foundation

struct ChatStreamChunk: Decodable {
    let model: String?
    let message: ChunkMessage?
    let eval_count: Int?
    let done: Bool
    let done_reason: String?

    struct ChunkMessage: Decodable {
        let role: String
        let content: String
        let thinking: String?
        let tool_calls: [ChunkToolCall]?
    }
}

struct ChunkToolCall: Decodable, Sendable {
    let id: String?
    let function: ChunkToolCallFunction
}

struct ChunkToolCallFunction: Decodable, Sendable {
    let name: String
    let arguments: [String: JSONValue]
}
