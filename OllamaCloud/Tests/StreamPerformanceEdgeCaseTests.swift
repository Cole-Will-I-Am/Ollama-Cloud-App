import XCTest
@testable import OllamaCloud

final class StreamPerformanceEdgeCaseTests: XCTestCase {
    func testBatchingForceFinalFlushPreservesTailChunks() {
        let simulation = StreamingChatService.simulateBatching(
            events: [
                .init(offsetMs: 0, content: "A"),
                .init(offsetMs: 10, content: "B")
            ],
            think: true,
            flushIntervalMs: 40,
            forceFinalFlush: true
        )

        XCTAssertEqual(simulation.finalContent, "AB")
        XCTAssertEqual(simulation.tokenCount, 2)
        XCTAssertGreaterThanOrEqual(simulation.flushCount, 1)
        XCTAssertEqual(
            simulation.flushes.map(\.contentDelta).joined(),
            simulation.finalContent
        )
    }

    func testBatchingThrottleReducesFlushCountForRapidTokens() {
        let events = (0..<20).map { index in
            StreamingChatService.StreamBatchingEvent(
                offsetMs: index * 5,
                content: "x"
            )
        }

        let simulation = StreamingChatService.simulateBatching(
            events: events,
            think: true,
            flushIntervalMs: 40,
            forceFinalFlush: true
        )

        XCTAssertEqual(simulation.finalContent.count, 20)
        XCTAssertEqual(simulation.tokenCount, 20)
        XCTAssertLessThan(simulation.flushCount, simulation.tokenCount)
        XCTAssertGreaterThanOrEqual(simulation.flushCount, 2)
    }

    func testBatchingIgnoresThinkingWhenDisabled() {
        let simulation = StreamingChatService.simulateBatching(
            events: [
                .init(offsetMs: 0, thinking: "t1"),
                .init(offsetMs: 20, thinking: "t2"),
                .init(offsetMs: 30, content: "answer")
            ],
            think: false,
            flushIntervalMs: 40,
            forceFinalFlush: true
        )

        XCTAssertEqual(simulation.finalThinking, "")
        XCTAssertEqual(simulation.finalContent, "answer")
        XCTAssertEqual(simulation.tokenCount, 1)
    }

    func testBatchingIncludesThinkingWhenEnabled() {
        let simulation = StreamingChatService.simulateBatching(
            events: [
                .init(offsetMs: 0, thinking: "t1"),
                .init(offsetMs: 10, thinking: "t2"),
                .init(offsetMs: 50, content: "A")
            ],
            think: true,
            flushIntervalMs: 40,
            forceFinalFlush: true
        )

        XCTAssertEqual(simulation.finalThinking, "t1t2")
        XCTAssertEqual(simulation.finalContent, "A")
        XCTAssertEqual(simulation.flushCount, 2)
        XCTAssertEqual(simulation.firstTokenMs, 50)
    }

    func testStreamingAutoScrollThrottleBoundary() {
        let base = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(
            ChatView.shouldTriggerStreamingAutoScroll(
                now: base.addingTimeInterval(0.099),
                lastAutoScrollAt: base,
                interval: 0.1
            )
        )
        XCTAssertTrue(
            ChatView.shouldTriggerStreamingAutoScroll(
                now: base.addingTimeInterval(0.1),
                lastAutoScrollAt: base,
                interval: 0.1
            )
        )
    }
}
