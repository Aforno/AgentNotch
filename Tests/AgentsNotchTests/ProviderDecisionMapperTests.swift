import AgentsNotchCore
import XCTest

final class ProviderDecisionMapperTests: XCTestCase {
    func testCodexPermissionAllowUsesDecisionBehavior() throws {
        let payload = try decode("""
        {
          "session_id": "thr",
          "cwd": "/tmp",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash"
        }
        """)
        let object = ProviderDecisionMapper.jsonObject(
            provider: .codex,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .allow)
        )
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
    }

    func testOnceDecisionUsesTheSameAllowPayload() throws {
        let payload = try decode("""
        {
          "session_id": "thr",
          "cwd": "/tmp",
          "hook_event_name": "PermissionRequest",
          "tool_name": "Bash"
        }
        """)
        let allow = ProviderDecisionMapper.jsonObject(
            provider: .codex,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .allow)
        )
        let once = ProviderDecisionMapper.jsonObject(
            provider: .codex,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .once)
        )
        XCTAssertEqual(
            allow["hookSpecificOutput"] as? NSDictionary,
            once["hookSpecificOutput"] as? NSDictionary
        )
    }

    func testPermissionDenyIncludesMessage() throws {
        let payload = try decode("""
        {
          "session_id": "thr",
          "cwd": "/tmp",
          "hook_event_name": "PermissionRequest"
        }
        """)
        let object = ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .deny)
        )
        let decision = try XCTUnwrap(
            (object["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        )
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(decision["message"] as? String, "Denied from Agents Notch")
    }

    func testPreToolUseOptionAllowSetsPermissionDecision() throws {
        let payload = try decode("""
        {
          "session_id": "q",
          "cwd": "/tmp",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion",
          "tool_input": {"questions": []}
        }
        """)
        let object = ProviderDecisionMapper.jsonObject(
            provider: .claudeCode,
            payload: payload,
            reply: AgentReply(replyId: UUID(), decision: .option, optionId: "option-0")
        )
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertEqual(output["permissionDecisionReason"] as? String, "Selected option-0")
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try AgentHookInput.decode(Data(json.utf8))
    }
}
