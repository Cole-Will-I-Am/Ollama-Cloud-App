import XCTest
@testable import OllamaCloud

final class OllamaAPIErrorTests: XCTestCase {
    func testTransientClassification() {
        XCTAssertTrue(OllamaAPIError.timeout.isTransient)
        XCTAssertTrue(OllamaAPIError.offline.isTransient)
        XCTAssertFalse(OllamaAPIError.unauthorized.isTransient)
        XCTAssertFalse(OllamaAPIError.rateLimited(retryAfter: nil).isTransient)
    }

    func testUserMessagesAreFriendly() {
        XCTAssertEqual(OllamaAPIError.timeout.userMessage, "Request timed out. Try again.")
        XCTAssertEqual(OllamaAPIError.unauthorized.userMessage, "Invalid API key. Remove it in Settings and re-enter.")
    }
}
