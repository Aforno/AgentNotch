import AgentsNotchCore
@testable import AgentsNotch
import XCTest

final class ActivityEventTimelineTests: XCTestCase {
    func testConsecutiveToolLifecycleEventsCollapseIntoOneSummary() {
        let start = Date(timeIntervalSince1970: 100)
        let events = [
            event(.toolCompleted, at: start.addingTimeInterval(3), activity: "Finished js"),
            event(.toolStarted, at: start, activity: "Using js"),
        ]

        let summaries = ActivityEventSummary.make(from: events)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].title, "Ran JavaScript")
        XCTAssertEqual(summaries[0].duration, 3)
        XCTAssertEqual(summaries[0].events.count, 2)
    }

    func testImportantEventBreaksToolSummary() {
        let start = Date(timeIntervalSince1970: 100)
        let events = [
            event(.toolCompleted, at: start.addingTimeInterval(2), activity: "Finished js"),
            event(.waiting, at: start.addingTimeInterval(1), activity: "Needs approval"),
            event(.toolStarted, at: start, activity: "Using js"),
        ]

        let summaries = ActivityEventSummary.make(from: events)

        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(summaries[1].title, "Needs approval")
    }

    func testToolCallIdentityPairsLifecycleAcrossImportantEvent() {
        let start = Date(timeIntervalSince1970: 100)
        let events = [
            event(.toolCompleted, at: start.addingTimeInterval(2), activity: "Finished js", callID: "call-1"),
            event(.waiting, at: start.addingTimeInterval(1), activity: "Needs approval"),
            event(.toolStarted, at: start, activity: "Using js", callID: "call-1"),
        ]

        let summaries = ActivityEventSummary.make(from: events)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].title, "Ran JavaScript")
        XCTAssertEqual(summaries[0].events.count, 2)
        XCTAssertEqual(summaries[0].duration, 2)
        XCTAssertEqual(summaries[1].title, "Needs approval")
    }

    func testFailedToolSummaryCarriesFailurePresentation() {
        let summary = ActivityEventSummary.make(from: [
            event(.toolCompleted, at: Date(timeIntervalSince1970: 100), activity: "Tool failed: Tests failed"),
        ])

        XCTAssertEqual(summary.first?.title, "Tool failed JavaScript")
        XCTAssertTrue(summary.first?.isFailure == true)
    }

    func testWhitespaceOnlyToolMetadataIsIgnored() {
        let events = [
            AgentEvent(
                type: .toolStarted,
                sessionId: "codex:test",
                provider: .codex,
                activity: "   ",
                timestamp: Date(timeIntervalSince1970: 100),
                metadata: ["tool": "   "]
            ),
        ]

        let summaries = ActivityEventSummary.make(from: events)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].kind, .event)
        XCTAssertEqual(summaries[0].title, AgentState.executingTool.displayName)
    }

    private func event(
        _ type: AgentEventType,
        at timestamp: Date,
        activity: String,
        callID: String? = nil
    ) -> AgentEvent {
        var metadata = ["tool": "mcp__node_repl__js"]
        metadata["toolCallId"] = callID
        return AgentEvent(
            type: type,
            sessionId: "codex:test",
            provider: .codex,
            activity: activity,
            timestamp: timestamp,
            metadata: metadata
        )
    }
}
