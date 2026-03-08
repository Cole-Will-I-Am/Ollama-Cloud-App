import Foundation

struct OpenAIStreamChunk: Decodable {
    let choices: [OpenAIChoice]?
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Decodable {
    let delta: OpenAIDelta?
    let finish_reason: String?
}

struct OpenAIDelta: Decodable {
    let role: String?
    let content: String?
    let tool_calls: [OpenAIToolCallDelta]?
}

struct OpenAIToolCallDelta: Decodable {
    let index: Int
    let id: String?
    let function: OpenAIFunctionDelta?
}

struct OpenAIFunctionDelta: Decodable {
    let name: String?
    let arguments: String?
}

struct OpenAIUsage: Decodable {
    let completion_tokens: Int?
}
