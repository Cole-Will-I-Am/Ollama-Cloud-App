import Foundation

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool
    let think: Bool
    let options: ChatOptions?
    let tools: [ChatTool]?

    init(model: String, messages: [ChatRequestMessage], stream: Bool = true, think: Bool = true, options: ChatOptions? = nil, tools: [ChatTool]? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.think = think
        self.options = options
        self.tools = tools
    }
}

struct ChatRequestMessage: Encodable {
    let role: String
    let content: String
    let images: [String]?
    let tool_name: String?
    let tool_call_id: String?

    init(role: String, content: String, images: [String]? = nil, tool_name: String? = nil, tool_call_id: String? = nil) {
        self.role = role
        self.content = content
        self.images = images
        self.tool_name = tool_name
        self.tool_call_id = tool_call_id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(images, forKey: .images)
        try container.encodeIfPresent(tool_name, forKey: .tool_name)
        try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
    }

    private enum CodingKeys: String, CodingKey {
        case role, content, images, tool_name, tool_call_id
    }
}

// MARK: - Tool Types (Ollama format)

struct ChatTool: Encodable {
    let type: String
    let function: ChatToolFunction

    init(function: ChatToolFunction) {
        self.type = "function"
        self.function = function
    }
}

struct ChatToolFunction: Encodable {
    let name: String
    let description: String
    let parameters: ChatToolParameters
}

struct ChatToolParameters: Encodable {
    let type: String
    let required: [String]?
    let properties: [String: ChatToolProperty]

    init(required: [String]? = nil, properties: [String: ChatToolProperty] = [:]) {
        self.type = "object"
        self.required = required
        self.properties = properties
    }
}

struct ChatToolProperty: Encodable {
    let type: String
    let description: String
    let `enum`: [String]?
    let items: ChatToolPropertyItems?

    init(type: String, description: String, enum enumValues: [String]? = nil, items: ChatToolPropertyItems? = nil) {
        self.type = type
        self.description = description
        self.enum = enumValues
        self.items = items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(`enum`, forKey: .enum)
        try container.encodeIfPresent(items, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case type, description, `enum`, items
    }
}

struct ChatToolPropertyItems: Encodable {
    let type: String
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
