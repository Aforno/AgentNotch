import AgentsNotchCore
import XCTest

@MainActor
final class GrokTurnSettlementReducerTests: XCTestCase {
    func testDelayedStopCancelledForOlderPromptDoesNotSettleNewerTurn() throws {
        let activity = AgentActivityService()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let firstPrompt = try map(
            #"{"sessionId":"grok_order","cwd":"/tmp/AgentNotch","hookEventName":"UserPromptSubmit","promptId":"prompt-a","prompt":"first"}"#,
            now: base
        )
        XCTAssertEqual(firstPrompt.metadata?["promptId"], "prompt-a")
        activity.ingest(firstPrompt)

        activity.ingest(try map(
            #"{"sessionId":"grok_order","cwd":"/tmp/AgentNotch","hookEventName":"UserPromptSubmit","promptId":"prompt-b","prompt":"second"}"#,
            now: base.addingTimeInterval(1)
        ))

        activity.ingest(try map(
            #"{"sessionId":"grok_order","cwd":"/tmp/AgentNotch","hookEventName":"StopCancelled","promptId":"prompt-a","reason":"user_interrupt"}"#,
            now: base.addingTimeInterval(2)
        ))

        let session = try XCTUnwrap(activity.sessions.first)
        XCTAssertEqual(session.state, .thinking)
        XCTAssertEqual(session.currentActivity, "Thinking")
        XCTAssertNil(session.completedAt)
    }

    func testIdlePromptDoesNotOverwriteKnownFailureOutcome() throws {
        let activity = AgentActivityService()
        let base = Date(timeIntervalSince1970: 1_700_000_100)

        activity.ingest(try map(
            #"{"sessionId":"grok_failure","cwd":"/tmp/AgentNotch","hookEventName":"UserPromptSubmit","promptId":"prompt-a","prompt":"work"}"#,
            now: base
        ))
        activity.ingest(try map(
            #"{"sessionId":"grok_failure","cwd":"/tmp/AgentNotch","hookEventName":"StopFailure","promptId":"prompt-a","error":"rate_limit"}"#,
            now: base.addingTimeInterval(1)
        ))

        var session = try XCTUnwrap(activity.sessions.first)
        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(session.currentActivity, "Usage limit reached")
        let failedAt = session.completedAt

        activity.ingest(try map(
            #"{"sessionId":"grok_failure","cwd":"/tmp/AgentNotch","hookEventName":"Notification","notificationType":"idle_prompt","message":"Waiting for your next prompt"}"#,
            now: base.addingTimeInterval(61)
        ))

        session = try XCTUnwrap(activity.sessions.first)
        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(session.currentActivity, "Usage limit reached")
        XCTAssertEqual(session.completedAt, failedAt)
    }

    func testIdlePromptDoesNotReplaceKnownSuccessfulOutcomeText() throws {
        let activity = AgentActivityService()
        let base = Date(timeIntervalSince1970: 1_700_000_200)

        activity.ingest(try map(
            #"{"sessionId":"grok_success","cwd":"/tmp/AgentNotch","hookEventName":"UserPromptSubmit","promptId":"prompt-a","prompt":"work"}"#,
            now: base
        ))
        activity.ingest(try map(
            #"{"sessionId":"grok_success","cwd":"/tmp/AgentNotch","hookEventName":"Stop","promptId":"prompt-a","reason":"end_turn","lastAssistantMessage":"Done cleanly"}"#,
            now: base.addingTimeInterval(1)
        ))
        activity.ingest(try map(
            #"{"sessionId":"grok_success","cwd":"/tmp/AgentNotch","hookEventName":"Notification","notificationType":"idle_prompt","message":"Waiting for your next prompt"}"#,
            now: base.addingTimeInterval(61)
        ))

        let session = try XCTUnwrap(activity.sessions.first)
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.currentActivity, "Done cleanly")
    }

    func testUnseenPromptIdStillSettlesAsGrokRequires() throws {
        let activity = AgentActivityService()
        let base = Date(timeIntervalSince1970: 1_700_000_300)

        activity.ingest(try map(
            #"{"sessionId":"grok_unseen","cwd":"/tmp/AgentNotch","hookEventName":"UserPromptSubmit","promptId":"prompt-a","prompt":"work"}"#,
            now: base
        ))
        activity.ingest(try map(
            #"{"sessionId":"grok_unseen","cwd":"/tmp/AgentNotch","hookEventName":"StopCancelled","promptId":"bash-turn-never-seen","reason":"user_interrupt"}"#,
            now: base.addingTimeInterval(1)
        ))

        let session = try XCTUnwrap(activity.sessions.first)
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.currentActivity, "Stopped")
    }

    func testNestedGrokStopFailureDoesNotFailParent() throws {
        let payload = try decode(
            #"{"sessionId":"grok_parent","cwd":"/tmp/AgentNotch","hookEventName":"StopFailure","promptId":"child-prompt","subagentType":"explore","error":"rate_limit"}"#
        )

        XCTAssertNil(AgentHookEventMapper.map(payload, provider: .grok))
    }

    private func map(_ json: String, now: Date) throws -> AgentEvent {
        let payload = try decode(json)
        return try XCTUnwrap(AgentHookEventMapper.map(payload, provider: .grok, now: now))
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try JSONDecoder().decode(AgentHookPayload.self, from: Data(json.utf8))
    }
}
