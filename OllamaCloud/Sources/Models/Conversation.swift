import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var title: String
    var modelName: String
    var systemPrompt: String
    var temperature: Double
    var topP: Double
    var topK: Int
    var numPredict: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(
        title: String = "New Chat",
        modelName: String = "",
        systemPrompt: String = "",
        temperature: Double = 0.7,
        topP: Double = 0.9,
        topK: Int = 40,
        numPredict: Int = 2048
    ) {
        self.id = UUID()
        self.title = title
        self.modelName = modelName
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.numPredict = numPredict
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}
