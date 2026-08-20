import AgentsNotchCore
import XCTest

final class AgentReplyPromptBuilderTests: XCTestCase {
    func testPermissionRequestIncludesCommandAndGrants() throws {
        let payload = try decode("""
        {
          "session_id": "thr_123",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash",
          "tool_input": {"command": "git push origin main --tags"}
        }
        """)
        let replyId = UUID()
        let pending = try XCTUnwrap(AgentReplyPromptBuilder.make(payload: payload, replyId: replyId))

        XCTAssertEqual(pending.replyId, replyId)
        XCTAssertEqual(pending.kind, .permission)
        XCTAssertEqual(pending.prompt, "Allow this command?")
        XCTAssertEqual(pending.detail, "git push origin main --tags")
        XCTAssertEqual(pending.grants, [.deny, .allow])
    }

    func testAskUserQuestionExtractsOptions() throws {
        let payload = try decode("""
        {
          "session_id": "q1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion",
          "tool_input": {
            "questions": [
              {
                "question": "Which migration strategy?",
                "options": [
                  {"label": "Expand in place"},
                  {"label": "New table"}
                ]
              }
            ]
          }
        }
        """)
        let pending = try XCTUnwrap(AgentReplyPromptBuilder.make(payload: payload, replyId: UUID()))

        XCTAssertEqual(pending.kind, .question)
        XCTAssertEqual(pending.prompt, "Which migration strategy?")
        XCTAssertEqual(pending.options.map(\.label), ["Expand in place", "New table"])
        XCTAssertEqual(pending.grants, [.deny])
        XCTAssertEqual(pending.questions?.first?.text, "Which migration strategy?")
    }

    func testExitPlanModeUsesPlanGrants() throws {
        let payload = try decode("""
        {
          "session_id": "plan",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "PreToolUse",
          "tool_name": "ExitPlanMode",
          "tool_input": {"plan": "Split hook install by config shape"}
        }
        """)
        let pending = try XCTUnwrap(AgentReplyPromptBuilder.make(payload: payload, replyId: UUID()))
        XCTAssertEqual(pending.kind, .plan)
        XCTAssertEqual(pending.grants, [.deny, .allow])
        XCTAssertEqual(pending.detail, "Split hook install by config shape")
    }

    func testOnlyCodexAndClaudeCanDecide() {
        XCTAssertTrue(AgentReplyPolicy.canDecide(provider: .codex))
        XCTAssertTrue(AgentReplyPolicy.canDecide(provider: .claudeCode))
        XCTAssertFalse(AgentReplyPolicy.canDecide(provider: .grok))
        XCTAssertFalse(AgentReplyPolicy.canDecide(provider: .geminiCLI))
        XCTAssertFalse(AgentReplyPolicy.canDecide(provider: .cursor))
        XCTAssertFalse(AgentReplyPolicy.canDecide(provider: .openCode))
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try AgentHookInput.decode(Data(json.utf8))
    }
}
