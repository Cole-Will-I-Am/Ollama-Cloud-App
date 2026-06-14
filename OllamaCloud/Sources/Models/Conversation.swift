import Foundation
import SwiftData

enum ThinkingMode: String, CaseIterable, Identifiable {
    case auto
    case on
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .on:
            return "On"
        case .off:
            return "Off"
        }
    }
}

@Model
final class Conversation {
    var id: UUID
    var title: String
    var isPinned: Bool?
    var accountScopeKey: String
    var modelName: String
    var apiProviderRaw: String?
    var thinkingModeRaw: String?
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

    var isProjectChat: Bool?      // nil/false = normal chat, true = project chat panel

    var projectID: UUID?          // nil = ungrouped chat, else the owning ChatProject.id (lightweight Projects)

    var activeLeafID: UUID?       // Tip of the currently viewed branch (nil = legacy linear fallback)

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    /// Messages along the active branch from root to leaf.
    /// Falls back to sorted-by-date for legacy conversations (activeLeafID == nil).
    var activeBranchMessages: [Message] {
        let sorted = messages.sorted { $0.createdAt < $1.createdAt }
        guard let leafID = activeLeafID else {
            return sorted
        }
        let branch = branchMessages(leafID: leafID)
        return branch.isEmpty ? sorted : branch
    }

    /// Walk from `leafID` up via parentID to build the branch in root→leaf order.
    func branchMessages(leafID: UUID) -> [Message] {
        let lookup = messages.reduce(into: [UUID: Message]()) { partialResult, message in
            partialResult[message.id] = message
        }
        var chain: [Message] = []
        var currentID: UUID? = leafID
        var visited: Set<UUID> = []

        while let id = currentID,
              visited.insert(id).inserted,
              let msg = lookup[id] {
            chain.append(msg)
            currentID = msg.parentID
        }
        return chain.reversed()
    }

    /// Walk DOWN from a message, always picking the most recently created child, until reaching a leaf.
    func findLeaf(from messageID: UUID) -> UUID {
        let childrenByParent = Dictionary(grouping: messages, by: { $0.parentID })
        var current = messageID
        var visited: Set<UUID> = []

        while visited.insert(current).inserted,
              let children = childrenByParent[current],
              !children.isEmpty {
            current = children
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .last!
                .id
        }
        return current
    }

    /// Converts legacy linear chats (all parentID == nil) into a linked chain and validates activeLeafID.
    /// Returns true if the conversation was mutated.
    @discardableResult
    func prepareBranchingState() -> Bool {
        let sorted = messages.sorted { $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else {
            if activeLeafID != nil {
                activeLeafID = nil
                return true
            }
            return false
        }

        var didChange = false

        if let activeLeafID {
            if !sorted.contains(where: { $0.id == activeLeafID }) {
                self.activeLeafID = sorted.last?.id
                didChange = true
            }
        }

        let hasParentLinks = sorted.contains { $0.parentID != nil }
        if !hasParentLinks {
            var previousID: UUID?
            for message in sorted {
                if message.parentID != previousID {
                    message.parentID = previousID
                    didChange = true
                }
                previousID = message.id
            }
            if activeLeafID != sorted.last?.id {
                activeLeafID = sorted.last?.id
                didChange = true
            }
            return didChange
        }

        if activeLeafID == nil {
            activeLeafID = sorted.last?.id
            didChange = true
        }

        return didChange
    }

    var apiProvider: APIProvider {
        get { APIProvider(rawValue: apiProviderRaw ?? "") ?? .ollama }
        set { apiProviderRaw = newValue.rawValue }
    }

    var thinkingMode: ThinkingMode {
        get { ThinkingMode(rawValue: thinkingModeRaw ?? ThinkingMode.auto.rawValue) ?? .auto }
        set { thinkingModeRaw = newValue.rawValue }
    }

    init(
        title: String = "New Chat",
        isPinned: Bool = false,
        accountScopeKey: String = "",
        modelName: String = "",
        thinkingModeRaw: String? = ThinkingMode.auto.rawValue,
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
        numThread: Int = 0,
        projectID: UUID? = nil
    ) {
        self.id = UUID()
        self.projectID = projectID
        self.title = title
        self.isPinned = isPinned
        self.accountScopeKey = accountScopeKey
        self.modelName = modelName
        self.thinkingModeRaw = thinkingModeRaw
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
