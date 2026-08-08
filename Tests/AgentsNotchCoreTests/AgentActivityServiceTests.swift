import AgentsNotchCore
import XCTest

final class AgentActivityServiceTests: XCTestCase {
    @MainActor
    func testEventsReduceIntoOneSessionWithoutLosingTask() {
        let service = AgentActivityService()
        let startedAt = Date(timeIntervalSince1970: 100)

        service.ingest(AgentEvent(
            type: .started,
            sessionId: "session-1",
            provider: .codex,
            task: "Fix authentication",
            activity: "Starting",
            state: .starting,
            timestamp: startedAt,
            workingDirectory: "/tmp/project"
        ))
        service.ingest(AgentEvent(
            type: .fileChanged,
            sessionId: "session-1",
            provider: .codex,
            activity: "Editing AuthService.swift",
            state: .editing,
            timestamp: startedAt.addingTimeInterval(2),
            file: "Sources/AuthService.swift"
        ))

        XCTAssertEqual(service.sessions.count, 1)
        XCTAssertEqual(service.sessions[0].task, "Fix authentication")
        XCTAssertEqual(service.sessions[0].state, .editing)
        XCTAssertEqual(service.sessions[0].recentFiles, ["Sources/AuthService.swift"])
        XCTAssertEqual(service.activeSessions.count, 1)
    }

    @MainActor
    func testAttentionSessionsSortBeforeOtherActiveSessions() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "running",
            provider: .codex,
            activity: "Running tests",
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "waiting",
            provider: .claudeCode,
            activity: "Waiting for input",
            state: .waitingForUser
        ))

        XCTAssertEqual(service.sessions.first?.id, "waiting")
        XCTAssertEqual(service.attentionCount, 1)
    }

    @MainActor
    func testCompletedSessionsCanBePruned() {
        let service = AgentActivityService()
        let oldDate = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "done",
            provider: .codex,
            activity: "Done",
            state: .completed,
            timestamp: oldDate
        ))

        service.pruneCompleted(olderThan: 10, now: oldDate.addingTimeInterval(11))
        XCTAssertTrue(service.sessions.isEmpty)
    }

    @MainActor
    func testRestoreDropsOrphanedGrokStartsButKeepsRealSessions() {
        let orphanedGrokStart = AgentSession(event: AgentEvent(
            type: .started,
            sessionId: "grok:probe",
            provider: .grok,
            activity: "Session started",
            state: .starting,
            metadata: ["hookEvent": "session_start"]
        ))
        let activeGrokTurn = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "grok:turn",
            provider: .grok,
            task: "Fix the active-session list",
            activity: "Thinking",
            state: .thinking,
            metadata: ["hookEvent": "user_prompt_submit"]
        ))
        let codexStart = AgentSession(event: AgentEvent(
            type: .started,
            sessionId: "codex:session",
            provider: .codex,
            activity: "Session started",
            state: .starting,
            metadata: ["hookEvent": "SessionStart"]
        ))

        let service = AgentActivityService(sessions: [orphanedGrokStart, activeGrokTurn, codexStart])

        XCTAssertEqual(Set(service.sessions.map(\.id)), ["grok:turn", "codex:session"])
    }

    @MainActor
    func testLateOlderEventDoesNotRegressCurrentState() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .toolStarted,
            sessionId: "ordered",
            provider: .codex,
            activity: "Running tests",
            state: .executingTool,
            timestamp: base.addingTimeInterval(2)
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "ordered",
            provider: .codex,
            task: "Useful task title",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))

        XCTAssertEqual(service.sessions[0].state, .executingTool)
        XCTAssertEqual(service.sessions[0].currentActivity, "Running tests")
        XCTAssertEqual(service.sessions[0].task, "Useful task title")
    }

    @MainActor
    func testCompletedSessionIgnoresLaterWaitingNotification() {
        let service = AgentActivityService()
        let completedAt = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "grok-session",
            provider: .grok,
            activity: "Task completed",
            state: .completed,
            timestamp: completedAt
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "grok-session",
            provider: .grok,
            activity: "Waiting for input",
            state: .waitingForUser,
            timestamp: completedAt.addingTimeInterval(60),
            metadata: ["hookEvent": "notification"]
        ))

        XCTAssertEqual(service.sessions[0].state, .completed)
        XCTAssertEqual(service.sessions[0].currentActivity, "Task completed")
        XCTAssertEqual(service.sessions[0].completedAt, completedAt)
        XCTAssertEqual(service.sessions[0].recentEvents.count, 2)
        XCTAssertNil(service.attentionEvent)
    }

    @MainActor
    func testNewPromptCanResumeCompletedSession() {
        let service = AgentActivityService()
        let completedAt = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "resumed-session",
            provider: .grok,
            activity: "Task completed",
            state: .completed,
            timestamp: completedAt
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "resumed-session",
            provider: .grok,
            task: "Continue the task",
            activity: "Thinking",
            state: .thinking,
            timestamp: completedAt.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.sessions[0].state, .thinking)
        XCTAssertEqual(service.sessions[0].task, "Continue the task")
        XCTAssertNil(service.sessions[0].completedAt)
    }

    @MainActor
    func testRoutineActivityDoesNotRequestAutomaticPresentation() {
        let service = AgentActivityService()
        let routineStates: [(AgentEventType, AgentState)] = [
            (.started, .starting),
            (.activity, .thinking),
            (.toolStarted, .executingTool),
            (.fileChanged, .editing),
            (.toolCompleted, .running),
            (.completed, .completed),
            (.failed, .failed),
        ]

        for (index, value) in routineStates.enumerated() {
            service.ingest(AgentEvent(
                type: value.0,
                sessionId: "routine-\(index)",
                provider: .codex,
                state: value.1
            ))
            XCTAssertNil(service.attentionEvent)
        }
    }

    @MainActor
    func testWaitingForUserPresentsUntilThatAgentResumes() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "permission",
            provider: .claudeCode,
            activity: "Needs command approval",
            state: .waitingForUser
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "permission")

        service.ingest(AgentEvent(
            type: .fileChanged,
            sessionId: "unrelated",
            provider: .grok,
            state: .editing
        ))
        XCTAssertEqual(service.attentionEvent?.sessionId, "permission")

        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "permission",
            provider: .claudeCode,
            state: .thinking
        ))
        XCTAssertNil(service.attentionEvent)
    }

    @MainActor
    func testResumingOneWaitingAgentFallsBackToAnotherStillWaiting() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "first",
            provider: .claudeCode,
            activity: "Needs command approval",
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "second",
            provider: .grok,
            activity: "Waiting for input",
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "second")

        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "second",
            provider: .grok,
            activity: "Thinking",
            state: .thinking,
            timestamp: base.addingTimeInterval(2)
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "first")
        XCTAssertEqual(service.attentionEvent?.activity, "Needs command approval")
    }

    @MainActor
    func testReplaceSessionsRestoresAttentionForWaitingAgents() {
        let waiting = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "restored",
            provider: .codex,
            activity: "Needs approval",
            state: .waitingForUser,
            timestamp: Date(timeIntervalSince1970: 100)
        ))
        let running = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "busy",
            provider: .claudeCode,
            activity: "Running tests",
            state: .running,
            timestamp: Date(timeIntervalSince1970: 101)
        ))

        let service = AgentActivityService()
        service.replaceSessions([waiting, running])

        XCTAssertEqual(service.attentionEvent?.sessionId, "restored")
        XCTAssertEqual(service.attentionEvent?.activity, "Needs approval")
        XCTAssertEqual(service.attentionEvent?.resolvedState, .waitingForUser)
    }

    @MainActor
    func testRemovingAttentionSessionFallsBackToRemainingWaiter() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "keep",
            provider: .codex,
            activity: "Waiting for input",
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "drop",
            provider: .claudeCode,
            activity: "Needs approval",
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "drop")
        service.removeSession(id: "drop")
        XCTAssertEqual(service.attentionEvent?.sessionId, "keep")
    }

    @MainActor
    func testRemovingSimulatorBatchClearsItsAttentionAndPreservesRealSessions() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "real",
            provider: .codex,
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "debug-plan",
            provider: .codex,
            state: .waitingForUser
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "debug-child",
            provider: .codex,
            state: .running,
            parentSessionId: "debug-plan"
        ))

        var notifications = 0
        service.onSessionsChanged = { _ in notifications += 1 }
        service.removeSessions(ids: ["debug-plan", "debug-child"])

        XCTAssertEqual(service.sessions.map(\.id), ["real"])
        XCTAssertNil(service.attentionEvent)
        XCTAssertEqual(notifications, 1)
    }

    @MainActor
    func testPlanAndWorkflowUpdatesReduceIntoSession() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "structured",
            provider: .codex,
            timestamp: base,
            plan: AgentPlan(
                steps: [AgentStep(id: "one", title: "Model it", status: .inProgress)],
                updatedAt: base
            ),
            workflowUpdate: AgentWorkflowUpdate(
                id: "ship",
                title: "Ship feature",
                status: .running
            )
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "structured",
            provider: .codex,
            timestamp: base.addingTimeInterval(1),
            workflowUpdate: AgentWorkflowUpdate(id: "ship", status: .completed)
        ))

        XCTAssertEqual(service.sessions[0].plan?.steps.first?.status, .inProgress)
        XCTAssertEqual(service.sessions[0].workflows.count, 1)
        XCTAssertEqual(service.sessions[0].workflows[0].title, "Ship feature")
        XCTAssertEqual(service.sessions[0].workflows[0].status, .completed)
    }

    @MainActor
    func testHierarchyKeepsAttentionSubagentWithParent() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "other",
            provider: .claudeCode,
            state: .running,
            timestamp: base.addingTimeInterval(3)
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "parent",
            provider: .codex,
            state: .running,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "child",
            provider: .codex,
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1),
            parentSessionId: "parent",
            agentRole: "reviewer"
        ))

        XCTAssertEqual(service.hierarchicalSessions.map(\.id), ["parent", "child", "other"])
        XCTAssertEqual(service.children(of: "parent").map(\.id), ["child"])
        XCTAssertEqual(service.parent(of: service.sessions.first { $0.id == "child" }!)?.id, "parent")
    }

    @MainActor
    func testListSessionsCapsAtThreeIncludingActive() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        for index in 0..<5 {
            service.ingest(AgentEvent(
                type: .completed,
                sessionId: "done-\(index)",
                provider: .codex,
                state: .completed,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "active",
            provider: .codex,
            state: .running,
            timestamp: base.addingTimeInterval(10)
        ))

        XCTAssertEqual(service.listSessions.map(\.id), ["active", "done-4", "done-3"])
        XCTAssertEqual(service.listSessions.count, 3)
    }

    @MainActor
    func testListSessionsShowsEveryActiveWhenMoreThanThree() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        for index in 0..<4 {
            service.ingest(AgentEvent(
                type: .activity,
                sessionId: "active-\(index)",
                provider: .codex,
                state: .running,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "done",
            provider: .claudeCode,
            state: .completed,
            timestamp: base.addingTimeInterval(20)
        ))

        XCTAssertEqual(service.listSessions.count, 4)
        XCTAssertEqual(Set(service.listSessions.map(\.id)), [
            "active-0", "active-1", "active-2", "active-3"
        ])
        XCTAssertFalse(service.listSessions.contains { $0.id == "done" })
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
}
