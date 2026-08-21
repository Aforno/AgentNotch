import AgentsNotchCore
import XCTest

final class ProviderDecisionMapperTests: XCTestCase {
    func testCodexPermissionAllowAndDenyMatchSchema() throws {
        let payload = try decode(permissionFixture)
        let allowed = try decision(provider: .codex, payload: payload, reply: .allow)
        XCTAssertEqual(allowed["behavior"] as? String, "allow")
        let denied = try decision(provider: .codex, payload: payload, reply: .deny)
        XCTAssertEqual(denied["behavior"] as? String, "deny")
        XCTAssertEqual(denied["message"] as? String, "Denied from Agent Notch")
    }

    func testClaudePermissionAllowAndDenyMatchSchema() throws {
        let payload = try decode(permissionFixture)
        let allowed = try decision(provider: .claudeCode, payload: payload, reply: .allow)
        let denied = try decision(provider: .claudeCode, payload: payload, reply: .deny)
        XCTAssertEqual(allowed["behavior"] as? String, "allow")
        XCTAssertEqual(denied["behavior"] as? String, "deny")
    }

    func testClaudeQuestionPreservesQuestionsAndMapsSingleAndMultiSelectLabels() throws {
        let payload = try decode(questionFixture)
        let output = try hookOutput(ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: payload,
            reply: AgentReply(
                replyId: UUID(),
                decision: .option,
                answers: ["Framework?": ["React"], "Targets?": ["iOS", "macOS"]]
            )
        ))
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        let input = try XCTUnwrap(output["updatedInput"] as? [String: Any])
        XCTAssertEqual((input["questions"] as? [[String: Any]])?.count, 2)
        let answers = try XCTUnwrap(input["answers"] as? [String: String])
        XCTAssertEqual(answers["Framework?"], "React")
        XCTAssertEqual(answers["Targets?"], "iOS, macOS")
        XCTAssertNil(input["agentsNotchSelectedOptionId"])
    }

    func testClaudeQuestionDenyDoesNotInventUpdatedInput() throws {
        let output = try hookOutput(ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: decode(questionFixture),
            reply: AgentReply(replyId: UUID(), decision: .deny)
        ))
        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertNil(output["updatedInput"])
    }

    func testClaudeExitPlanModeAllowPreservesInputAndDenyOmitsIt() throws {
        let payload = try decode(planFixture)
        let allowed = try hookOutput(ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .allow)
        ))
        let input = try XCTUnwrap(allowed["updatedInput"] as? [String: Any])
        XCTAssertEqual(input["plan"] as? String, "## Ship it")
        XCTAssertEqual(input["planFilePath"] as? String, "/tmp/plan.md")

        let denied = try hookOutput(ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .deny)
        ))
        XCTAssertEqual(denied["permissionDecision"] as? String, "deny")
        XCTAssertNil(denied["updatedInput"])
    }

    func testClaudeElicitationAcceptDeclineAndCancelMatchSchema() throws {
        let payload = try decode(elicitationFixture)
        let accepted = try hookOutput(ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .allow, content: .object(["username": .string("alice")]))
        ))
        XCTAssertEqual(accepted["action"] as? String, "accept")
        XCTAssertEqual((accepted["content"] as? [String: Any])?["username"] as? String, "alice")

        for (reply, expected) in [(AgentReplyDecision.deny, "decline"), (.cancel, "cancel")] {
            let output = try hookOutput(ProviderDecisionMapper.jsonObject(
                provider: .claudeCode,
                payload: payload,
                reply: AgentReply(replyId: UUID(), decision: reply)
            ))
            XCTAssertEqual(output["action"] as? String, expected)
            XCTAssertNil(output["decision"])
        }
    }

    private var permissionFixture: String {
        """
        {
          "session_id": "thr",
          "cwd": "/tmp",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash"
        }
        """
    }

    private var questionFixture: String {
        """
        {
          "session_id": "q",
          "cwd": "/tmp",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion",
          "tool_input": {
            "questions": [
              {
                "question": "Framework?",
                "header": "Framework",
                "options": [{"label": "React"}, {"label": "Vue"}],
                "multiSelect": false
              },
              {
                "question": "Targets?",
                "header": "Targets",
                "options": [{"label": "iOS"}, {"label": "macOS"}],
                "multiSelect": true
              }
            ]
          }
        }
        """
    }

    private var planFixture: String {
        """
        {
          "session_id": "p",
          "cwd": "/tmp",
          "hook_event_name": "PreToolUse",
          "tool_name": "ExitPlanMode",
          "tool_input": {
            "plan": "## Ship it",
            "planFilePath": "/tmp/plan.md"
          }
        }
        """
    }

    private var elicitationFixture: String {
        """
        {
          "session_id": "e",
          "cwd": "/tmp",
          "hook_event_name": "Elicitation",
          "mcp_server_name": "accounts",
          "message": "Username"
        }
        """
    }

    private func decision(
        provider: AgentProvider,
        payload: AgentHookPayload,
        reply: AgentReplyDecision
    ) throws -> [String: Any] {
        let object = ProviderDecisionMapper.jsonObject(
            provider: provider,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: reply)
        )
        return try XCTUnwrap(try hookOutput(object)["decision"] as? [String: Any])
    }

    private func hookOutput(_ object: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try AgentHookInput.decode(Data(json.utf8))
    }
}
