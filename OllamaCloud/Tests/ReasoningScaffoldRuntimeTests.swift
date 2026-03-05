import XCTest
import SwiftData
@testable import OllamaCloud

@MainActor
final class ReasoningScaffoldRuntimeTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Conversation.self,
            Message.self,
            ReasoningScaffold.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    func testResolverClearsScopeMismatchedActiveScaffold() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let scaffold = ReasoningScaffold(
            accountScopeKey: "scope-a",
            name: "Scoped",
            role: "Analyst",
            perspective: "Specific",
            reasoningSteps: ["step"]
        )
        context.insert(scaffold)

        let conversation = Conversation(
            activeScaffoldID: scaffold.id.uuidString,
            activeScaffoldName: scaffold.name
        )
        context.insert(conversation)
        try context.save()

        let resolution = ReasoningScaffoldResolver.resolveActiveScaffold(
            for: conversation,
            in: context,
            scopeKey: "scope-b"
        )

        XCTAssertNil(resolution.scaffold)
        XCTAssertTrue(resolution.cleared)
        XCTAssertEqual(resolution.reason, "scope_mismatch_ui")
        XCTAssertNil(conversation.activeScaffoldID)
        XCTAssertNil(conversation.activeScaffoldName)
    }

    func testReferenceCleanerClearsDanglingConversationPointers() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let scaffold = ReasoningScaffold(
            accountScopeKey: "scope",
            name: "ToDelete",
            role: "Guide",
            perspective: "Clear",
            reasoningSteps: ["step"]
        )
        context.insert(scaffold)

        let referenced = Conversation(
            title: "A",
            activeScaffoldID: scaffold.id.uuidString,
            activeScaffoldName: scaffold.name
        )
        let untouched = Conversation(title: "B")
        context.insert(referenced)
        context.insert(untouched)
        try context.save()

        let cleared = ReasoningScaffoldReferenceCleaner.clearReferences(
            to: scaffold.id,
            in: context
        )

        XCTAssertEqual(cleared, 1)
        XCTAssertNil(referenced.activeScaffoldID)
        XCTAssertNil(referenced.activeScaffoldName)
        XCTAssertNil(untouched.activeScaffoldID)
        XCTAssertNil(untouched.activeScaffoldName)
    }

    func testPrepareScaffoldSystemPromptClearsMissingScaffoldAndUpdatesTimestamp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldDate = Date(timeIntervalSince1970: 1000)

        let conversation = Conversation(
            activeScaffoldID: UUID().uuidString,
            activeScaffoldName: "Ghost"
        )
        conversation.updatedAt = oldDate
        context.insert(conversation)
        try context.save()

        let service = StreamingChatService()
        let resolution = service.prepareScaffoldSystemPrompt(
            conversation: conversation,
            modelContext: context
        )

        XCTAssertNil(resolution.systemPrompt)
        XCTAssertTrue(resolution.stateChanged)
        XCTAssertNil(conversation.activeScaffoldID)
        XCTAssertNil(conversation.activeScaffoldName)
        XCTAssertGreaterThan(conversation.updatedAt, oldDate)
        XCTAssertEqual(service.notice, "Active reasoning scaffold is missing and was cleared.")
    }

    func testPrepareScaffoldSystemPromptClearsInvalidIDAndUpdatesTimestamp() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldDate = Date(timeIntervalSince1970: 1000)

        let conversation = Conversation(
            activeScaffoldID: "not-a-uuid",
            activeScaffoldName: "Broken"
        )
        conversation.updatedAt = oldDate
        context.insert(conversation)
        try context.save()

        let service = StreamingChatService()
        let resolution = service.prepareScaffoldSystemPrompt(
            conversation: conversation,
            modelContext: context
        )

        XCTAssertNil(resolution.systemPrompt)
        XCTAssertTrue(resolution.stateChanged)
        XCTAssertNil(conversation.activeScaffoldID)
        XCTAssertNil(conversation.activeScaffoldName)
        XCTAssertGreaterThan(conversation.updatedAt, oldDate)
        XCTAssertEqual(service.notice, "Active reasoning scaffold could not be loaded and was cleared.")
    }

    func testPrepareScaffoldSystemPromptClearsScopeMismatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oldDate = Date(timeIntervalSince1970: 1000)

        let scaffold = ReasoningScaffold(
            accountScopeKey: "other-scope",
            name: "WrongScope",
            role: "Guide",
            perspective: "Test",
            reasoningSteps: ["step"]
        )
        context.insert(scaffold)

        let conversation = Conversation(
            activeScaffoldID: scaffold.id.uuidString,
            activeScaffoldName: scaffold.name
        )
        conversation.updatedAt = oldDate
        context.insert(conversation)
        try context.save()

        let service = StreamingChatService()
        let resolution = service.prepareScaffoldSystemPrompt(
            conversation: conversation,
            modelContext: context
        )

        XCTAssertNil(resolution.systemPrompt)
        XCTAssertTrue(resolution.stateChanged)
        XCTAssertNil(conversation.activeScaffoldID)
        XCTAssertNil(conversation.activeScaffoldName)
        XCTAssertGreaterThan(conversation.updatedAt, oldDate)
        XCTAssertEqual(
            service.notice,
            "Active reasoning scaffold was from another account scope and was cleared."
        )
    }
}
