import XCTest
@testable import OllamaCloud

final class ChatRequestEncodingTests: XCTestCase {
    func testChatRequestEncodesExpectedFields() throws {
        let request = ChatRequest(
            model: "llama3.2",
            messages: [
                ChatRequestMessage(role: "system", content: "You are concise."),
                ChatRequestMessage(role: "user", content: "Hello")
            ],
            options: ChatOptions(temperature: 0.4, top_p: 0.85, num_thread: 8)
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let options = try XCTUnwrap(json["options"] as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])

        XCTAssertEqual(json["model"] as? String, "llama3.2")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["think"] as? Bool, true)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[1]["content"] as? String, "Hello")
        let temperature = try XCTUnwrap((options["temperature"] as? NSNumber)?.doubleValue)
        let topP = try XCTUnwrap((options["top_p"] as? NSNumber)?.doubleValue)
        XCTAssertEqual(temperature, 0.4, accuracy: 0.0001)
        XCTAssertEqual(topP, 0.85, accuracy: 0.0001)
        XCTAssertEqual(options["num_thread"] as? Int, 8)
    }

    func testOutboundMessagesPlaceScaffoldSystemMessageBeforeSystemPrompt() {
        let user = Message(role: "user", content: "Hello")
        user.createdAt = Date(timeIntervalSince1970: 1_000)
        let assistant = Message(role: "assistant", content: "Hi there")
        assistant.createdAt = Date(timeIntervalSince1970: 1_010)

        let outbound = StreamingChatService.buildOutboundMessages(
            conversationMessages: [assistant, user],
            systemPrompt: "System prompt",
            scaffoldSystemPrompt: "Scaffold prompt"
        )

        XCTAssertEqual(outbound.count, 4)
        XCTAssertEqual(outbound[0].role, "system")
        XCTAssertEqual(outbound[0].content, "Scaffold prompt")
        XCTAssertEqual(outbound[1].role, "system")
        XCTAssertEqual(outbound[1].content, "System prompt")
        XCTAssertEqual(outbound[2].role, "user")
        XCTAssertEqual(outbound[3].role, "assistant")
    }
}
