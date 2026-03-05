import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var isPinned: Bool?
    var modelName: String
    var systemPrompt: String
    var activeScaffoldID: String?
    var activeScaffoldName: String?
    var createdAt: Date
    var updatedAt: Date

    // Sampling
    var temperature: Double
    var topP: Double
    var topK: Int
    var minP: Double
    var typicalP: Double

    // Penalties
    var repeatPenalty: Double
    var repeatLastN: Int
    var presencePenalty: Double
    var frequencyPenalty: Double

    // Engine
    var numPredict: Int
    var seed: Int
    var numBatch: Int
    var numThread: Int

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        title: String = "New Chat",
        isPinned: Bool = false,
        modelName: String = "",
        systemPrompt: String = "",
        activeScaffoldID: String? = nil,
        activeScaffoldName: String? = nil,
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        minP: Double = 0.0,
        typicalP: Double = 1.0,
        repeatPenalty: Double = 1.1,
        repeatLastN: Int = 64,
        presencePenalty: Double = 0.0,
        frequencyPenalty: Double = 0.0,
        numPredict: Int = 2048,
        seed: Int = 0,
        numBatch: Int = 512,
        numThread: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.isPinned = isPinned
        self.modelName = modelName
        self.systemPrompt = systemPrompt
        self.activeScaffoldID = activeScaffoldID
        self.activeScaffoldName = activeScaffoldName
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.minP = minP
        self.typicalP = typicalP
        self.repeatPenalty = repeatPenalty
        self.repeatLastN = repeatLastN
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.numPredict = numPredict
        self.seed = seed
        self.numBatch = numBatch
        self.numThread = numThread
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}
