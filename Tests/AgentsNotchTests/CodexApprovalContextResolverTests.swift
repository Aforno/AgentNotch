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

    func testTranscriptReviewerComesFromMatchingTurnContext() throws {
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-approval-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: transcript) }
        try Data("""
        {"type":"turn_context","payload":{"turn_id":"turn-1","approvals_reviewer":"auto_review"}}
        {"type":"response_item","payload":{"output":"grep turn_context turn-1 user"}}
        {"type":"turn_context","payload":{"turn_id":"turn-2","approvals_reviewer":"user"}}
        """.utf8).write(to: transcript)

        func requiresUserInput(turnId: String) throws -> Bool {
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: try decode("""
            {"session_id":"s","hook_event_name":"PermissionRequest",
             "transcript_path":"\(transcript.path)","turn_id":"\(turnId)"}
            """))
        }
        XCTAssertFalse(try requiresUserInput(turnId: "turn-1"))
        XCTAssertTrue(try requiresUserInput(turnId: "turn-2"))
        XCTAssertTrue(try requiresUserInput(turnId: "missing"))
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try JSONDecoder().decode(AgentHookPayload.self, from: Data(json.utf8))
    }
}
