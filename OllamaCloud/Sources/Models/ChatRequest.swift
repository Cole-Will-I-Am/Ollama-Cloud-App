import Foundation

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool
    let think: Bool
    let options: ChatOptions?

    init(model: String, messages: [ChatRequestMessage], stream: Bool = true, think: Bool = true, options: ChatOptions? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.think = think
        self.options = options
    }
}

struct ChatRequestMessage: Encodable {
    let role: String
    let content: String
    let images: [String]?

    init(role: String, content: String, images: [String]? = nil) {
        self.role = role
        self.content = content
        self.images = images
    }
}

struct ChatOptions: Encodable {
    // Sampling
    let temperature: Double?
    let top_p: Double?
    let top_k: Int?
    let min_p: Double?
    let typical_p: Double?

    // Penalties
    let repeat_penalty: Double?
    let repeat_last_n: Int?
    let presence_penalty: Double?
    let frequency_penalty: Double?

    // Engine
    let num_predict: Int?
    let seed: Int?
    let num_batch: Int?
    let num_thread: Int?

    init(
        temperature: Double? = nil,
        top_p: Double? = nil,
        top_k: Int? = nil,
        min_p: Double? = nil,
        typical_p: Double? = nil,
        repeat_penalty: Double? = nil,
        repeat_last_n: Int? = nil,
        presence_penalty: Double? = nil,
        frequency_penalty: Double? = nil,
        num_predict: Int? = nil,
        seed: Int? = nil,
        num_batch: Int? = nil,
        num_thread: Int? = nil
    ) {
        self.temperature = temperature
        self.top_p = top_p
        self.top_k = top_k
        self.min_p = min_p
        self.typical_p = typical_p
        self.repeat_penalty = repeat_penalty
        self.repeat_last_n = repeat_last_n
        self.presence_penalty = presence_penalty
        self.frequency_penalty = frequency_penalty
        self.num_predict = num_predict
        self.seed = seed
        self.num_batch = num_batch
        self.num_thread = num_thread
    }
}
