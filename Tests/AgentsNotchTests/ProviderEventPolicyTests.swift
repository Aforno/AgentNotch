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
