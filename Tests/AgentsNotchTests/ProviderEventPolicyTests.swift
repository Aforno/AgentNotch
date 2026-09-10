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

    func testIdlePromptIsATurnSettledNotificationOnlyForGrok() {
        XCTAssertTrue(ProviderEventPolicy.isTurnSettledNotification("idle_prompt", provider: .grok))
        XCTAssertFalse(ProviderEventPolicy.isTurnSettledNotification("idle_prompt", provider: .claudeCode))
        XCTAssertFalse(ProviderEventPolicy.isTurnSettledNotification("idle_prompt", provider: .codex))
        XCTAssertFalse(ProviderEventPolicy.isTurnSettledNotification("idle_prompt", provider: .geminiCLI))
        XCTAssertFalse(ProviderEventPolicy.isTurnSettledNotification("idle_prompt", provider: .cursor))
        XCTAssertTrue(ProviderEventPolicy.isTurnSettledNotification("task_complete", provider: .claudeCode))
        XCTAssertFalse(ProviderEventPolicy.isTurnSettledNotification("permission_prompt", provider: .grok))
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

        XCTAssertEqual(
            ProviderEventPolicy.stopFailureActivity(from: try decode(#"""
            {
              "sessionId": "s",
              "cwd": "/tmp",
              "hookEventName": "stop_failure",
              "error": "overloaded"
            }
            """#)),
            "Provider overloaded"
        )

        let unknownCancel = try decode(#"""
        {
          "sessionId": "s",
          "cwd": "/tmp",
          "hookEventName": "stop_cancelled"
        }
        """#)
        let unknownOutcome = ProviderEventPolicy.stopCancelledOutcome(from: unknownCancel)
        XCTAssertEqual(unknownOutcome.state, .completed)
        XCTAssertEqual(unknownOutcome.activity, "Stopped")
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
