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

    func testGrokParentScopedSubagentIsRemapped() throws {
        let payload = try decode(#"""
        {
          "sessionId": "parent",
          "cwd": "/tmp",
          "hookEventName": "subagent_start"
        }
        """#)
        XCTAssertTrue(
            ProviderEventPolicy.remapsParentScopedSubagent(
                provider: .grok,
                payload: payload,
                parentSessionId: nil
            )
        )
        XCTAssertFalse(
            ProviderEventPolicy.remapsParentScopedSubagent(
                provider: .codex,
                payload: payload,
                parentSessionId: nil
            )
        )
    }

    func testClaudeInteractiveToolsWaitForTheUser() throws {
        let payload = try decode(#"""
        {
          "sessionId": "s",
          "cwd": "/tmp",
          "hookEventName": "PreToolUse",
          "tool_name": "AskUserQuestion",
          "tool_input": { "questions": [{ "question": "Ship it?" }] }
        }
        """#)
        XCTAssertTrue(ProviderEventPolicy.isInteractiveTool(payload.toolName))
        XCTAssertEqual(ProviderEventPolicy.interactiveToolActivity(for: payload), "Ship it?")
    }

    func testCodexPlanAndGoalSnapshotsStayOnTheCodexPolicy() throws {
        let payload = try decode(#"""
        {
          "sessionId": "s",
          "cwd": "/tmp",
          "hookEventName": "PreToolUse",
          "tool_name": "update_plan",
          "tool_input": {
            "title": "Ship",
            "plan": [{ "step": "Inspect", "status": "in_progress" }]
          }
        }
        """#)
        let now = Date(timeIntervalSince1970: 100)
        let plan = try XCTUnwrap(
            CodexEventPolicy.planSnapshot(from: payload, tool: "update_plan", now: now)
        )
        XCTAssertEqual(plan.title, "Ship")
        XCTAssertEqual(plan.steps.first?.title, "Inspect")
        XCTAssertEqual(plan.steps.first?.status, .inProgress)
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try JSONDecoder().decode(AgentHookPayload.self, from: Data(json.utf8))
    }
}
