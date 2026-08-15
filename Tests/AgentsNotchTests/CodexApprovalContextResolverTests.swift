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

    func testHookApprovalsReviewerWinsOverTranscript() throws {
        let fixture = try TranscriptFixture(
            lines: [
                #"{"type":"turn_context","payload":{"turn_id":"turn-1","approvals_reviewer":"auto_review"}}"#,
            ]
        )
        defer { fixture.remove() }

        let payload = try decode("""
        {
          "session_id": "s",
          "cwd": "/tmp",
          "hook_event_name": "PermissionRequest",
          "transcript_path": "\(fixture.url.path)",
          "turn_id": "turn-1",
          "approvals_reviewer": "user"
        }
        """)

        XCTAssertTrue(
            CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload),
            "When Codex includes approvals_reviewer on the hook, ignore the transcript tail."
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

private struct TranscriptFixture {
    let url: URL

    init(lines: [String]) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-approval-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
