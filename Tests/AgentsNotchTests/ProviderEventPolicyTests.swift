import XCTest
@testable import AgentsNotchCore

final class ProviderEventPolicyTests: XCTestCase {
    func testGrokSessionStartIsInvisible() {
        XCTAssertFalse(
            ProviderEventPolicy.shouldMapSessionStart(provider: .grok, source: nil)
        )
        XCTAssertTrue(
            ProviderEventPolicy.shouldMapSessionStart(provider: .codex, source: nil)
        )
        XCTAssertFalse(
            ProviderEventPolicy.shouldMapSessionStart(provider: .codex, source: "resume")
        )
    }

    func testGrokIdlePromptIsATurnSettledNotification() {
        XCTAssertTrue(GrokEventPolicy.isTurnSettledNotification("idle_prompt"))
        XCTAssertTrue(GrokEventPolicy.isTurnSettledNotification("task_complete"))
        XCTAssertFalse(GrokEventPolicy.isTurnSettledNotification("permission_prompt"))
    }

    func testStopFailureAndCancelledOutcomesAreReadable() throws {
        let rateLimit = try decode(#"""
        {
          "sessionId": "s",
          "cwd": "/tmp",
          "hookEventName": "stop_failure",
          "error": "rate_limit"
        }
        """#)
        XCTAssertEqual(ProviderEventPolicy.stopFailureActivity(from: rateLimit), "Usage limit reached")

        let truncated = try decode(#"""
        {
          "sessionId": "s",
          "cwd": "/tmp",
          "hookEventName": "stop_failure",
          "error": "max_output_tokens"
        }
        """#)
        XCTAssertEqual(ProviderEventPolicy.stopFailureActivity(from: truncated), "Output limit reached")

        let maxTurns = try decode(#"""
        {
          "sessionId": "s",
          "cwd": "/tmp",
          "hookEventName": "stop_cancelled",
          "reason": "max_turns"
        }
        """#)
        let outcome = ProviderEventPolicy.stopCancelledOutcome(from: maxTurns)
        XCTAssertEqual(outcome.state, .failed)
        XCTAssertEqual(outcome.activity, "Turn limit reached")
    }

    func testGrokParentScopedSubagentIsRemapped() throws {
        let payload = try decode(#"""
        {
          "sessionId": "parent",
          "cwd": "/tmp",
          "hookEventName": "subagent_start"
        }
        """#)
        XCTAssertTrue(
            GrokEventPolicy.remapsParentScopedSubagent(
                provider: .grok,
                payload: payload,
                parentSessionId: nil
            )
        )
        XCTAssertFalse(
            GrokEventPolicy.remapsParentScopedSubagent(
                provider: .codex,
                payload: payload,
                parentSessionId: nil
            )
        )
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try JSONDecoder().decode(AgentHookPayload.self, from: Data(json.utf8))
    }
}
