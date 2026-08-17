#if DEBUG
@testable import AgentsNotch
import AgentsNotchCore
import XCTest

@MainActor
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

    func testHeadlineLeadsWithTaskAndProjectInsteadOfProvider() {
        let session = session(
            id: "root",
            state: .running,
            task: "Fix authentication",
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: false),
            "Fix authentication · AgentNotch"
        )
    }

    func testHeadlineHidesTaskInPrivacyMode() {
        let session = session(
            id: "root",
            state: .running,
            task: "Fix authentication",
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: true),
            "AgentNotch"
        )
    }

    func testHeadlineOmitsImageOnlyTask() {
        let session = session(
            id: "root",
            state: .running,
            task: "[Image #1]",
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: false),
            "AgentNotch"
        )
    }

    func testHeadlineOmitsUserQueryMarkupTag() {
        let session = session(
            id: "root",
            state: .completed,
            task: "<user_query>",
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: false),
            "AgentNotch"
        )
    }

    func testHeadlineOmitsPlaceholderTask() {
        let session = session(
            id: "root",
            state: .running,
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: false),
            "AgentNotch"
        )
    }

    func testHeadlineUsesTaskAloneWhenProjectIsMissing() {
        let session = session(id: "root", state: .running, task: "Fix authentication")

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: false),
            "Fix authentication"
        )
    }

    func testSubagentHeadlineIsTaskOnly() {
        let session = session(
            id: "child",
            parentID: "root",
            state: .running,
            task: "Review auth module",
            workingDirectory: "/Users/me/AgentNotch",
            agentRole: "audit:core-models"
        )

        XCTAssertEqual(
            AgentRowPresentation.headline(for: session, privacyModeEnabled: false),
            "Review auth module"
        )
        XCTAssertEqual(
            AgentRowPresentation.formattedRole(session.agentRole),
            "Audit Core Models"
        )
    }

    func testFormattedRoleFallsBackToSubagent() {
        XCTAssertEqual(AgentRowPresentation.formattedRole(nil), "Subagent")
        XCTAssertEqual(AgentRowPresentation.formattedRole("  "), "Subagent")
    }

    func testListHeightDoesNotReserveChromeRowWhenSessionsAreVisible() {
        let first = session(id: "one", state: .running)
        let second = session(id: "two", state: .running)

        XCTAssertEqual(AgentListView.rowsHeight(for: []), DynamicIslandSpacing.rowHeight)
        XCTAssertEqual(
            AgentListView.rowsHeight(for: [first, second]),
            DynamicIslandSpacing.rowHeight * 2
        )
    }

    func testListControlsAlignWithMenuBarCenter() {
        let menuBarHeight: CGFloat = 32
        let topInset = menuBarHeight + DynamicIslandSpacing.expandedTop
        let originalCenter = topInset + DynamicIslandSpacing.chromeHeight / 2

        let offset = AgentListView.controlsVerticalOffset(
            topInset: topInset,
            menuBarHeight: menuBarHeight
        )

        XCTAssertEqual(originalCenter + offset, menuBarHeight / 2)
    }

    private func session(
        id: String,
        parentID: String? = nil,
        state: AgentState,
        task: String? = nil,
        workingDirectory: String? = nil,
        agentRole: String? = nil
    ) -> AgentSession {
        AgentSession(event: AgentEvent(
            type: state == .completed ? .completed : .activity,
            sessionId: id,
            provider: .codex,
            task: task,
            state: state,
            workingDirectory: workingDirectory,
            parentSessionId: parentID,
            agentRole: agentRole
        ))
    }
}
#endif
