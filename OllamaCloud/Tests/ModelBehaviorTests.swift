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
        XCTAssertNil(conversation.activeScaffoldID)
        XCTAssertNil(conversation.activeScaffoldName)
        XCTAssertEqual(conversation.temperature, 0.7, accuracy: 0.0001)
        XCTAssertEqual(conversation.topP, 0.9, accuracy: 0.0001)
        XCTAssertEqual(conversation.topK, 40)
        XCTAssertEqual(conversation.numPredict, 2048)
        XCTAssertTrue(conversation.messages.isEmpty)
    }
}
