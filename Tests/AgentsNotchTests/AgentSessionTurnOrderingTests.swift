import AgentsNotchCore
import XCTest

final class AgentSessionTurnOrderingTests: XCTestCase {
    @MainActor
    func testPreviousTurnTerminalCannotSettleNewPromptOrItsChild() throws {
        for terminalType in [AgentEventType.completed, .failed] {
            let service = AgentActivityService()
            service.ingest(event(.activity, at: 110, hook: "UserPromptSubmit"))
            service.ingest(AgentEvent(
                type: .toolStarted,
                sessionId: "codex:child",
                provider: .codex,
                timestamp: Date(timeIntervalSince1970: 111),
                parentSessionId: "codex:turns"
            ))

            service.ingest(event(terminalType, at: 109, hook: "Stop"))

            let session = try XCTUnwrap(service.session(id: "codex:turns"))
            XCTAssertEqual(session.state, .running)
            XCTAssertNil(session.completedAt)
            XCTAssertEqual(service.session(id: "codex:child")?.state, .executingTool)

            service.ingest(event(.toolStarted, at: 112))
            XCTAssertEqual(service.session(id: session.id)?.state, .executingTool)
        }
    }

    func testCurrentTurnTerminalStillWinsOverReorderedToolActivity() {
        var session = AgentSession(event: event(.activity, at: 100, hook: "UserPromptSubmit"))
        session.apply(event(.toolStarted, at: 103))

        XCTAssertTrue(session.apply(event(.completed, at: 102, hook: "Stop")))
        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.completedAt, Date(timeIntervalSince1970: 102))
        XCTAssertEqual(session.updatedAt, Date(timeIntervalSince1970: 103))
    }

    func testLatePromptStillEstablishesTurnBoundary() {
        var session = AgentSession(event: event(.toolStarted, at: 110))
        session.apply(event(.activity, at: 109, hook: "UserPromptSubmit"))

        XCTAssertFalse(session.apply(event(.completed, at: 108, hook: "Stop")))
        XCTAssertEqual(session.state, .executingTool)
    }

    func testTurnBoundarySurvivesHistoryEvictionAndPersistence() throws {
        var session = AgentSession(event: event(.activity, at: 100, hook: "UserPromptSubmit"))
        for offset in 1...AgentSession.recentEventLimit {
            session.apply(event(.toolStarted, at: 100 + TimeInterval(offset)))
        }
        XCTAssertFalse(session.recentEvents.contains { $0.metadata?["hookEvent"] == "UserPromptSubmit" })
        let data = try JSONEncoder.agentsNotch.encode(session)
        session = try JSONDecoder.agentsNotch.decode(AgentSession.self, from: data)

        XCTAssertFalse(session.apply(event(.completed, at: 99, hook: "Stop")))
        XCTAssertEqual(session.state, .executingTool)
    }

    func testLegacyHistoryRecoversTurnBoundaryFromPrompt() throws {
        let session = AgentSession(event: event(.activity, at: 100, hook: "UserPromptSubmit"))
        let encoded = try JSONEncoder.agentsNotch.encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "latestTurnStartedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        var restored = try JSONDecoder.agentsNotch.decode(AgentSession.self, from: legacyData)

        XCTAssertFalse(restored.apply(event(.completed, at: 99, hook: "Stop")))
        XCTAssertEqual(restored.state, .running)
    }

    private func event(_ type: AgentEventType, at seconds: TimeInterval, hook: String? = nil) -> AgentEvent {
        AgentEvent(
            type: type,
            sessionId: "codex:turns",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: seconds),
            metadata: hook.map { ["hookEvent": $0] }
        )
    }
}
