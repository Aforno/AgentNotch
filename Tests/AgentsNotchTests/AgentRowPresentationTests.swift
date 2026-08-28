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

    func testRowSplitsTaskFromProjectSoTheProjectSurvivesTruncation() {
        let session = session(
            id: "root",
            state: .running,
            task: "Fix authentication",
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.taskTitle(for: session, privacyModeEnabled: false),
            "Fix authentication"
        )
        XCTAssertEqual(
            AgentRowPresentation.projectChip(for: session, privacyModeEnabled: false),
            "AgentNotch"
        )
    }

    func testProjectChipIsOmittedWhenItWouldRepeatTheTitle() {
        let noTask = session(id: "a", state: .running, workingDirectory: "/Users/me/AgentNotch")
        let taskOnly = session(id: "b", state: .running, task: "Fix authentication")
        let subagent = session(
            id: "c",
            parentID: "a",
            state: .running,
            task: "Review auth module",
            workingDirectory: "/Users/me/AgentNotch",
            agentRole: "auditor"
        )

        XCTAssertEqual(AgentRowPresentation.taskTitle(for: noTask, privacyModeEnabled: false), "AgentNotch")
        XCTAssertNil(AgentRowPresentation.projectChip(for: noTask, privacyModeEnabled: false))
        XCTAssertNil(AgentRowPresentation.projectChip(for: taskOnly, privacyModeEnabled: false))
        // Subagents inherit the parent's project, so repeating it is noise.
        XCTAssertNil(AgentRowPresentation.projectChip(for: subagent, privacyModeEnabled: false))
    }

    func testPrivacyModeHidesTheTaskAndTheProjectChip() {
        let session = session(
            id: "root",
            state: .running,
            task: "Fix authentication",
            workingDirectory: "/Users/me/AgentNotch"
        )

        XCTAssertEqual(
            AgentRowPresentation.taskTitle(for: session, privacyModeEnabled: true),
            "AgentNotch"
        )
        XCTAssertNil(AgentRowPresentation.projectChip(for: session, privacyModeEnabled: true))
    }

    func testReconnectingStateIsNotRenderedAsRunningWork() {
        // A session that was active when the app quit must not borrow the
        // running spinner, or a dead agent looks like a working one.
        XCTAssertTrue(agentStatePresentation(for: .running).showsSpinner)
        XCTAssertFalse(agentStatePresentation(for: .unknown).showsSpinner)
        XCTAssertFalse(agentStatePresentation(for: .unknown).systemImage.isEmpty)
    }

    func testActiveStatesShareOneHueAndAreSeparatedByGlyph() {
        let active: [AgentState] = [.starting, .running, .executingTool, .thinking, .editing]
        XCTAssertEqual(Set(active.map { agentStateColor(for: $0).description }).count, 1)

        // Non-spinner active states still need distinct glyphs.
        let glyphs = [AgentState.thinking, .editing].map { agentStatePresentation(for: $0).systemImage }
        XCTAssertEqual(Set(glyphs).count, glyphs.count)
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
