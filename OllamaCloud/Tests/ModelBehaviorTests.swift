import XCTest
@testable import OllamaCloud

final class ModelBehaviorTests: XCTestCase {
    func testOllamaModelDisplayNameStripsTagSuffix() {
        let tagged = OllamaModel(name: "llama3.2:latest", model: nil, modified_at: nil, size: nil)
        let plain = OllamaModel(name: "qwen3", model: nil, modified_at: nil, size: nil)

        XCTAssertEqual(tagged.displayName, "llama3.2")
        XCTAssertEqual(plain.displayName, "qwen3")
    }

    func testConversationDefaults() {
        let conversation = Conversation()

        XCTAssertEqual(conversation.title, "New Chat")
        XCTAssertFalse(conversation.isPinned ?? false)
        XCTAssertTrue(conversation.accountScopeKey.isEmpty)
        XCTAssertTrue(conversation.modelName.isEmpty)
        XCTAssertEqual(conversation.thinkingMode, .auto)
        XCTAssertNil(conversation.activeScaffoldID)
        XCTAssertNil(conversation.activeScaffoldName)
        XCTAssertEqual(conversation.temperature, 0.7, accuracy: 0.0001)
        XCTAssertEqual(conversation.topP, 0.9, accuracy: 0.0001)
        XCTAssertEqual(conversation.topK, 40)
        XCTAssertEqual(conversation.numPredict, 2048)
        XCTAssertTrue(conversation.messages.isEmpty)
    }

    func testThinkingModeAutoUsesModelProfileDefault() {
        XCTAssertFalse(
            SeerAssistantProfile.shouldEnableThinking(
                for: AppConfig.seerModelName,
                mode: .auto
            )
        )
        XCTAssertTrue(
            SeerAssistantProfile.shouldEnableThinking(
                for: "qwen3.5:32b",
                mode: .auto
            )
        )
    }

    func testThinkingModeOverrideForcesOnOrOff() {
        XCTAssertFalse(
            SeerAssistantProfile.shouldEnableThinking(
                for: AppConfig.seerModelName,
                mode: .on
            )
        )
        XCTAssertTrue(
            SeerAssistantProfile.shouldEnableThinking(
                for: "qwen3.5:32b",
                mode: .on
            )
        )
        XCTAssertFalse(
            SeerAssistantProfile.shouldEnableThinking(
                for: "qwen3.5:32b",
                mode: .off
            )
        )
    }

    // A reasoning model that emitted only thinking (empty content) on a clean finish should
    // have that thinking promoted to the visible answer — otherwise the message renders with
    // no answer bubble, only a collapsed THINKING panel ("I can't see your output").
    func testEmptyContentWithThinkingPromotesThinkingToAnswer() {
        let resolved = StreamingChatService.resolveStreamOutput(
            content: "",
            thinking: "Question 2: Is it a concrete noun?",
            cancelled: false,
            failed: false
        )
        XCTAssertEqual(resolved.content, "Question 2: Is it a concrete noun?")
        XCTAssertEqual(resolved.thinking, "")
    }

    // Well-behaved responses (non-empty content) keep content and thinking separate.
    func testNonEmptyContentLeavesThinkingInItsOwnChannel() {
        let resolved = StreamingChatService.resolveStreamOutput(
            content: "Question 2: Is it a concrete noun?",
            thinking: "The user said yes, so it's a noun. Continue.",
            cancelled: false,
            failed: false
        )
        XCTAssertEqual(resolved.content, "Question 2: Is it a concrete noun?")
        XCTAssertEqual(resolved.thinking, "The user said yes, so it's a noun. Continue.")
    }

    // Cancelled or failed streams are NOT promoted — the cancel path renders its own
    // "[stopped during thinking]" placeholder, and a failure surfaces an error instead.
    func testCancelledOrFailedEmptyContentIsNotPromoted() {
        let cancelled = StreamingChatService.resolveStreamOutput(
            content: "", thinking: "partial reasoning", cancelled: true, failed: false
        )
        XCTAssertEqual(cancelled.content, "")
        XCTAssertEqual(cancelled.thinking, "partial reasoning")

        let failed = StreamingChatService.resolveStreamOutput(
            content: "", thinking: "partial reasoning", cancelled: false, failed: true
        )
        XCTAssertEqual(failed.content, "")
        XCTAssertEqual(failed.thinking, "partial reasoning")
    }

    func testSeerMergedPromptIncludesPlatformCapabilityGuidance() throws {
        try XCTSkipIf(!AppConfig.seerModelEnabled, "SEER profile disabled in this environment")

        let prompt = SeerAssistantProfile.mergedSystemPrompt(
            baseSystemPrompt: "",
            selectedModelName: AppConfig.seerModelName
        )

        XCTAssertTrue(prompt.contains("For feature questions, always distinguish iOS vs macOS behavior."))
        XCTAssertTrue(prompt.contains("Platform capability baseline:"))
        XCTAssertTrue(prompt.contains("macOS only: MCP tools/servers"))
        XCTAssertTrue(prompt.contains("iOS limitations vs macOS: no MCP tools"))
        XCTAssertTrue(prompt.contains("When a feature is unavailable on one platform"))
        XCTAssertTrue(prompt.contains("environment-dependent behavior"))
    }
}
