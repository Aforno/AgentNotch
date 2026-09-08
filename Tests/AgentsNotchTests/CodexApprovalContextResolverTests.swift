import XCTest
@testable import AgentsNotchCore

final class CodexApprovalContextResolverTests: XCTestCase {
    func testNonPermissionRequestNeverReadsTranscript() throws {
        let payload = try decode(#"""
        {
          "session_id": "s",
          "cwd": "/tmp",
          "hook_event_name": "PreToolUse",
          "transcript_path": "/tmp/this-file-must-not-be-opened.jsonl",
          "turn_id": "turn-1"
        }
        """#)
        XCTAssertTrue(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    func testAutomaticReviewerOnHookSuppressesAttentionWithoutDisk() throws {
        let payload = try decode(#"""
        {
          "session_id": "s",
          "cwd": "/tmp",
          "hook_event_name": "PermissionRequest",
          "transcript_path": "/tmp/this-file-must-not-be-opened.jsonl",
          "turn_id": "turn-1",
          "approvals_reviewer": "auto_review"
        }
        """#)
        XCTAssertFalse(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
        )
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try JSONDecoder().decode(AgentHookPayload.self, from: Data(json.utf8))
    }
}
