#if DEBUG
@testable import AgentsNotch
import AgentsNotchCore
import XCTest

final class DebugEventSimulatorTests: XCTestCase {
    @MainActor
    func testResetRemovesOnlySimulatorSessionsAndClearsAttention() {
        let activity = AgentActivityService()
        activity.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:real-session",
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

        XCTAssertEqual(activity.sessions.map(\.id), ["codex:real-session"])
        XCTAssertNil(activity.attentionEvent)
    }
}
#endif
