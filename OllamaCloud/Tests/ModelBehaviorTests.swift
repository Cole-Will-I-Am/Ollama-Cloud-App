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
