import AgentsNotchCore
@testable import AgentsNotch
import XCTest

@MainActor
final class ActivityCenterProjectionTests: XCTestCase {
    func testGroupedProjectionUsesProjectRootAndExpandableChildren() {
        let now = Date(timeIntervalSince1970: 10_000)
        let root = makeSession(
            id: "codex:root",
            task: "Root task",
            timestamp: now,
            directory: "/tmp/AgentNotch"
        )
        let child = makeSession(
            id: "codex:child",
            task: "Worker task",
            timestamp: now.addingTimeInterval(1),
            directory: "/tmp/AgentNotch",
            parentID: root.id
        )
        let projection = ActivityCenterProjection()

        projection.update(
            sessions: [child, root],
            searchText: "",
            providerFilter: "all",
            statusFilter: .all,
            now: now
        )

        XCTAssertEqual(projection.projectGroups.map(\.title), ["AgentNotch"])
        XCTAssertEqual(projection.projectGroups.first?.groups.first?.root.id, root.id)
        XCTAssertEqual(projection.projectGroups.first?.groups.first?.children.map(\.id), [child.id])
        XCTAssertEqual(projection.groupID(containing: child.id), root.id)
    }

    func testSearchIncludesFilesEventsPlansAndWorkflows() {
        let now = Date(timeIntervalSince1970: 20_000)
        let plan = AgentPlan(
            title: "Release",
            steps: [AgentStep(id: "ship", title: "Ship telescope", status: .inProgress)],
            updatedAt: now
        )
        var session = AgentSession(event: AgentEvent(
            type: .fileChanged,
            sessionId: "codex:search",
            provider: .codex,
            task: "Unrelated title",
            activity: "Touched Router.swift",
            timestamp: now,
            workingDirectory: "/tmp/Search",
            file: "/tmp/Search/Router.swift",
            plan: plan,
            workflowUpdate: AgentWorkflowUpdate(
                id: "deploy",
                title: "Canary rollout",
                status: .running,
                steps: [AgentStep(id: "observe", title: "Observe metrics", status: .pending)]
            )
        ))
        session.currentActivity = "Working"
        let projection = ActivityCenterProjection()

        for query in ["Router.swift", "Ship telescope", "Canary rollout", "Observe metrics"] {
            projection.update(
                sessions: [session],
                searchText: query,
                providerFilter: "all",
                statusFilter: .all,
                now: now
            )
            XCTAssertEqual(projection.filteredSessions.map(\.id), [session.id], "Missing search result for \(query)")
        }
    }

    func testProjectAndDateFiltersCompose() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = makeSession(
            id: "codex:recent",
            task: "Recent",
            timestamp: now.addingTimeInterval(-60),
            directory: "/tmp/Recent"
        )
        let old = makeSession(
            id: "codex:old",
            task: "Old",
            timestamp: now.addingTimeInterval(-9 * 24 * 60 * 60),
            directory: "/tmp/Old"
        )
        let projection = ActivityCenterProjection()

        projection.update(
            sessions: [old, recent],
            searchText: "",
            providerFilter: "all",
            statusFilter: .all,
            projectFilter: "/tmp/Recent",
            dateFilter: .sevenDays,
            now: now
        )

        XCTAssertEqual(projection.filteredSessions.map(\.id), [recent.id])
        XCTAssertEqual(Set(projection.availableProjects.map(\.title)), ["Recent", "Old"])
    }

    private func makeSession(
        id: String,
        task: String,
        timestamp: Date,
        directory: String,
        parentID: String? = nil
    ) -> AgentSession {
        AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: id,
            provider: .codex,
            task: task,
            activity: "Working",
            state: .running,
            timestamp: timestamp,
            workingDirectory: directory,
            parentSessionId: parentID
        ))
    }
}
