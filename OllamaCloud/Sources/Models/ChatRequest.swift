import Foundation

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool
    let options: ChatOptions?

    init(model: String, messages: [ChatRequestMessage], stream: Bool = true, options: ChatOptions? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
    }
}

struct ChatRequestMessage: Encodable {
    let role: String
    let content: String
}

struct ChatOptions: Encodable {
    let temperature: Double?
    let top_p: Double?
    let top_k: Int?
    let num_predict: Int?

    init(temperature: Double? = nil, top_p: Double? = nil, top_k: Int? = nil, num_predict: Int? = nil) {
        self.temperature = temperature
        self.top_p = top_p
        self.top_k = top_k
        self.num_predict = num_predict
    }
}
