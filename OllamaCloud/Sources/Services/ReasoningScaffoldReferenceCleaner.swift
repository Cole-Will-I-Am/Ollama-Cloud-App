import Foundation
import SwiftData

@MainActor
enum ReasoningScaffoldReferenceCleaner {
    @discardableResult
    static func clearReferences(
        to scaffoldID: UUID,
        in modelContext: ModelContext
    ) -> Int {
        let scaffoldIDString = scaffoldID.uuidString
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate<Conversation> { conversation in
                conversation.activeScaffoldID == scaffoldIDString
            }
        )

        guard let conversations = try? modelContext.fetch(descriptor),
              !conversations.isEmpty else {
            return 0
        }

        let now = Date()
        for conversation in conversations {
            conversation.activeScaffoldID = nil
            conversation.activeScaffoldName = nil
            conversation.updatedAt = now
        }
        return conversations.count
    }
}
