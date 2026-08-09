#if DEBUG
@testable import AgentsNotch
import AgentsNotchCore
import XCTest

final class AgentRowPresentationTests: XCTestCase {
    func testDescendantSessionsIncludesNestedSubagentsAndStopsAtCycles() {
        let root = session(id: "root", parentID: "grandchild", state: .running)
        let child = session(id: "child", parentID: "root", state: .completed)
        let grandchild = session(id: "grandchild", parentID: "child", state: .running)
        let unrelated = session(id: "unrelated", state: .running)

        let descendants = AgentListView.descendantSessions(
            of: root,
            in: [root, child, grandchild, unrelated]
        )

        XCTAssertEqual(Set(descendants.map(\.id)), ["child", "grandchild"])
        XCTAssertEqual(descendants.filter(\.isActive).map(\.id), ["grandchild"])
    }

    func testVisibleStepsKeepsCurrentStepInsideSixCapsules() throws {
        let steps = (0..<9).map { index in
            AgentStep(
                id: "step-\(index)",
                title: "Step \(index)",
                status: index < 7 ? .completed : (index == 7 ? .inProgress : .pending)
            )
        }

        let visible = AgentRowPresentation.visibleSteps(in: steps)

        XCTAssertEqual(visible.count, 6)
        XCTAssertEqual(visible.last?.id, "step-7")
        XCTAssertTrue(visible.contains(where: { $0.status == .inProgress }))
    }

    func testCurrentStepPrefersInProgressOverEarlierBlockedStep() {
        let steps = [
            AgentStep(id: "blocked", title: "Old blocker", status: .blocked),
            AgentStep(id: "current", title: "Current work", status: .inProgress),
        ]

        XCTAssertEqual(AgentRowPresentation.currentStep(in: steps)?.id, "current")
    }

    private func session(
        id: String,
        parentID: String? = nil,
        state: AgentState
    ) -> AgentSession {
        AgentSession(event: AgentEvent(
            type: state == .completed ? .completed : .activity,
            sessionId: id,
            provider: .codex,
            state: state,
            parentSessionId: parentID
        ))
    }
}
#endif
