import Foundation
import SwiftData

@MainActor
enum ReasoningScaffoldResolver {
    struct Resolution {
        let scaffold: ReasoningScaffold?
        let cleared: Bool
        let reason: String?
    }

    static func resolveActiveScaffold(
        for conversation: Conversation,
        in modelContext: ModelContext,
        scopeKey: String = AccountScope.currentKey()
    ) -> Resolution {
        guard let rawID = conversation.activeScaffoldID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawID.isEmpty else {
            return Resolution(scaffold: nil, cleared: false, reason: nil)
        }

        guard let scaffoldID = UUID(uuidString: rawID) else {
            return clearConversationScaffold(
                conversation: conversation,
                in: modelContext,
                reason: "invalid_id_ui"
            )
        }

        let descriptor = FetchDescriptor<ReasoningScaffold>(
            predicate: #Predicate<ReasoningScaffold> { scaffold in
                scaffold.id == scaffoldID
            }
        )

        guard let scaffold = try? modelContext.fetch(descriptor).first else {
            return clearConversationScaffold(
                conversation: conversation,
                in: modelContext,
                reason: "missing_ui"
            )
        }

        guard scaffold.accountScopeKey == scopeKey else {
            return clearConversationScaffold(
                conversation: conversation,
                in: modelContext,
                reason: "scope_mismatch_ui"
            )
        }

        if conversation.activeScaffoldName != scaffold.name {
            conversation.activeScaffoldName = scaffold.name
            conversation.updatedAt = Date()
            try? modelContext.save()
        }

        return Resolution(scaffold: scaffold, cleared: false, reason: nil)
    }

    private static func clearConversationScaffold(
        conversation: Conversation,
        in modelContext: ModelContext,
        reason: String
    ) -> Resolution {
        let hadScaffold = (conversation.activeScaffoldID?.isEmpty == false)
            || (conversation.activeScaffoldName?.isEmpty == false)
        conversation.activeScaffoldID = nil
        conversation.activeScaffoldName = nil
        conversation.updatedAt = Date()
        try? modelContext.save()
        if hadScaffold {
            AppTelemetry.track("scaffold_cleared", metadata: ["reason": reason])
        }
        return Resolution(scaffold: nil, cleared: hadScaffold, reason: reason)
    }
}
