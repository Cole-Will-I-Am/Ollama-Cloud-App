import Foundation
import SwiftData

@Model
final class ReasoningScaffold {
    var id: UUID
    var accountScopeKey: String
    var name: String
    var summary: String
    var role: String
    var perspective: String
    var tone: String
    var reasoningStepsJSON: String
    var outputFormat: String
    var mustIncludeJSON: String
    var neverIncludeJSON: String
    var disclaimersJSON: String
    var prohibitedActionsJSON: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(
        accountScopeKey: String,
        name: String,
        summary: String = "",
        role: String,
        perspective: String,
        tone: String = "",
        reasoningSteps: [String],
        outputFormat: String = "",
        mustInclude: [String] = [],
        neverInclude: [String] = [],
        disclaimers: [String] = [],
        prohibitedActions: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = UUID()
        self.accountScopeKey = accountScopeKey
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        self.perspective = perspective.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reasoningStepsJSON = Self.encodeList(reasoningSteps)
        self.outputFormat = outputFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mustIncludeJSON = Self.encodeList(mustInclude)
        self.neverIncludeJSON = Self.encodeList(neverInclude)
        self.disclaimersJSON = Self.encodeList(disclaimers)
        self.prohibitedActionsJSON = Self.encodeList(prohibitedActions)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }

    var reasoningSteps: [String] {
        get { Self.decodeList(reasoningStepsJSON) }
        set {
            reasoningStepsJSON = Self.encodeList(newValue)
            updatedAt = Date()
        }
    }

    var mustInclude: [String] {
        get { Self.decodeList(mustIncludeJSON) }
        set {
            mustIncludeJSON = Self.encodeList(newValue)
            updatedAt = Date()
        }
    }

    var neverInclude: [String] {
        get { Self.decodeList(neverIncludeJSON) }
        set {
            neverIncludeJSON = Self.encodeList(newValue)
            updatedAt = Date()
        }
    }

    var disclaimers: [String] {
        get { Self.decodeList(disclaimersJSON) }
        set {
            disclaimersJSON = Self.encodeList(newValue)
            updatedAt = Date()
        }
    }

    var prohibitedActions: [String] {
        get { Self.decodeList(prohibitedActionsJSON) }
        set {
            prohibitedActionsJSON = Self.encodeList(newValue)
            updatedAt = Date()
        }
    }

    static func decodeList(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func encodeList(_ list: [String]) -> String {
        let normalized = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let data = try? JSONEncoder().encode(normalized),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}

extension ReasoningScaffold: Identifiable {}
