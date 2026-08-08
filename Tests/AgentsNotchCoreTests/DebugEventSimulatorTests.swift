#if DEBUG
@testable import AgentsNotch
import AgentsNotchCore
import XCTest

final class DebugEventSimulatorTests: XCTestCase {
    @MainActor
    func testPlanOptionProducesReferenceStyleProgress() throws {
        let activity = AgentActivityService()
        let simulator = DebugEventSimulator(activity: activity)

        simulator.simulatePlan()

        let session = try XCTUnwrap(activity.sessions.first)
        let plan = try XCTUnwrap(session.plan)
        XCTAssertEqual(session.task, "Add regression tests and run suite")
        XCTAssertEqual(plan.completedStepCount, 2)
        XCTAssertEqual(plan.steps.map(\.status), [.completed, .completed, .inProgress])
        XCTAssertEqual(session.recentEvents.first?.metadata?["source"], "simulator")
    }

    @MainActor
    func testResetCancelsAndRemovesOnlySimulatorSessions() {
        let activity = AgentActivityService()
        activity.ingest(AgentEvent(
            type: .activity,
            sessionId: "real-session",
            provider: .codex,
            state: .running
        ))
        let simulator = DebugEventSimulator(activity: activity)
        simulator.simulatePlan()
        simulator.simulateWorkflow()
        simulator.simulateSubagents()

        XCTAssertTrue(activity.sessions.contains(where: DebugEventSimulator.isSimulated))
        XCTAssertNotNil(activity.attentionEvent)

        simulator.reset()

        XCTAssertEqual(activity.sessions.map(\.id), ["real-session"])
        XCTAssertNil(activity.attentionEvent)
    }

    @MainActor
    func testLegacySimulatorSessionIsRecognizedForCleanup() {
        let legacy = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "simulator-primary",
            provider: .codex,
            state: .running
        ))

        XCTAssertTrue(DebugEventSimulator.isSimulated(legacy))
    }
}
#endif
