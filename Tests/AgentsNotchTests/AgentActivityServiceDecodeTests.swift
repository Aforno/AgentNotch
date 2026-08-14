import AgentsNotchCore
import Foundation
import XCTest

extension AgentActivityServiceTests {
    func testLegacyCompletedSessionDecodeRepairsUnfinishedPlan() throws {
        let base = Date(timeIntervalSince1970: 100)
        var session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "legacy-plan",
            provider: .codex,
            timestamp: base,
            plan: AgentPlan(
                steps: [AgentStep(id: "one", title: "Verify", status: .inProgress)],
                updatedAt: base
            )
        ))
        session.state = .completed
        session.completedAt = base.addingTimeInterval(1)
        session.updatedAt = base.addingTimeInterval(1)

        let data = try JSONEncoder.agentsNotch.encode(session)
        let decoded = try JSONDecoder.agentsNotch.decode(AgentSession.self, from: data)

        XCTAssertEqual(decoded.plan?.steps.first?.status, .completed)
        XCTAssertEqual(decoded.plan?.updatedAt, session.completedAt)
    }

    @MainActor
    func testLegacyPersistedSessionDecodesWithoutExecutionFields() throws {
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "legacy",
            provider: .codex,
            activity: "Running",
            state: .running
        ))
        let encoded = try JSONEncoder.agentsNotch.encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "parentSessionId")
        object.removeValue(forKey: "agentRole")
        object.removeValue(forKey: "plan")
        object.removeValue(forKey: "workflows")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.agentsNotch.decode(AgentSession.self, from: legacyData)
        XCTAssertFalse(decoded.isSubagent)
        XCTAssertNil(decoded.plan)
        XCTAssertTrue(decoded.workflows.isEmpty)
    }

    @MainActor
    func testPersistedUserQueryMarkupTaskIsTreatedAsUntitled() throws {
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "wrapped",
            provider: .grok,
            task: "Keep this while encoding",
            activity: "Hovering the notch now shows the job, not the vendor.",
            state: .completed,
            workingDirectory: "/Users/me/AgentNotch"
        ))
        let encoded = try JSONEncoder.agentsNotch.encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["task"] = "<user_query>"
        let dirty = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.agentsNotch.decode(AgentSession.self, from: dirty)
        XCTAssertEqual(decoded.task, AgentTaskTitle.untitled)
    }
}
