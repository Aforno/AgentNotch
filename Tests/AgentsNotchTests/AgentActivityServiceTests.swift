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
    func testDayBasedHistoryRetentionHasNoHiddenSessionCountCap() {
        let service = AgentActivityService()
        let base = Date().addingTimeInterval(-60)
        for index in 0..<25 {
            service.ingest(AgentEvent(
                type: .completed,
                sessionId: "completed-\(index)",
                provider: .codex,
                state: .completed,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }

        service.pruneCompleted(olderThan: 7 * 24 * 60 * 60)

        XCTAssertEqual(service.recentSessions.count, 25)
    }

    @MainActor
    func testActiveProvidersAreUniqueAndOrderedByLatestActivity() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex-old",
            provider: .codex,
            state: .running,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "claude",
            provider: .claudeCode,
            state: .thinking,
            timestamp: base.addingTimeInterval(2)
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex-new",
            provider: .codex,
            state: .editing,
            timestamp: base.addingTimeInterval(3)
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "grok-done",
            provider: .grok,
            state: .running,
            timestamp: base.addingTimeInterval(3.5)
        ))
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "grok-done",
            provider: .grok,
            state: .completed,
            timestamp: base.addingTimeInterval(4)
        ))

        XCTAssertEqual(service.activeProviders, [.codex, .claudeCode])
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
            timestamp: completedAt.addingTimeInterval(1),
            metadata: ["hookEvent": "user_prompt_submit"]
        ))

        XCTAssertEqual(service.sessions[0].state, .thinking)
        XCTAssertEqual(service.sessions[0].task, "Continue the task")
        XCTAssertNil(service.sessions[0].completedAt)
    }

    @MainActor
    func testCompletedSessionIgnoresDelayedRoutineActivityAtSameOrLaterTime() {
        let service = AgentActivityService()
        let completedAt = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "terminal",
            provider: .grok,
            state: .completed,
            timestamp: completedAt
        ))

        for (index, eventType) in [AgentEventType.activity, .toolStarted, .toolCompleted, .fileChanged].enumerated() {
            service.ingest(AgentEvent(
                type: eventType,
                sessionId: "terminal",
                provider: .grok,
                state: .running,
                timestamp: completedAt.addingTimeInterval(TimeInterval(index))
            ))
        }

        XCTAssertEqual(service.sessions[0].state, .completed)
        XCTAssertEqual(service.sessions[0].completedAt, completedAt)
        XCTAssertEqual(service.sessions[0].recentEvents.count, 5)
    }

    @MainActor
    func testFutureTimestampCannotPinSessionAheadOfCompletion() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "clock-skew",
            provider: .codex,
            state: .running,
            timestamp: Date().addingTimeInterval(10_000_000)
        ))
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "clock-skew",
            provider: .codex,
            state: .completed,
            timestamp: Date()
        ))

        XCTAssertEqual(service.sessions[0].state, .completed)
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
    func testSuccessfulCompletionFinalizesUnfinishedPlanSteps() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "planned",
            provider: .codex,
            timestamp: base,
            plan: AgentPlan(
                steps: [
                    AgentStep(id: "one", title: "Inspect", status: .completed),
                    AgentStep(id: "two", title: "Implement", status: .inProgress),
                    AgentStep(id: "three", title: "Verify", status: .pending),
                ],
                updatedAt: base
            )
        ))

        let completedAt = base.addingTimeInterval(1)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "planned",
            provider: .codex,
            activity: "Shipped",
            timestamp: completedAt
        ))

        XCTAssertEqual(service.sessions[0].state, .completed)
        XCTAssertEqual(service.sessions[0].currentActivity, "Shipped")
        XCTAssertEqual(service.sessions[0].plan?.steps.map(\.status), [.completed, .completed, .completed])
        XCTAssertEqual(service.sessions[0].plan?.updatedAt, completedAt)
        XCTAssertEqual(service.sessions[0].plan?.isComplete, true)
    }

    @MainActor
    func testImageFollowUpDoesNotReplaceExistingTask() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "thread",
            provider: .grok,
            task: "UI improvement recommendations no file edits",
            activity: "Thinking",
            state: .thinking
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "thread",
            provider: .grok,
            task: "[Image #1]",
            activity: "Thinking",
            state: .thinking
        ))

        XCTAssertEqual(service.sessions[0].task, "UI improvement recommendations no file edits")
    }

    @MainActor
    func testLateStartCorrectsSessionStartTimeWithoutRegressingState() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "ordered-start",
            provider: .codex,
            state: .running,
            timestamp: base.addingTimeInterval(10)
        ))
        service.ingest(AgentEvent(
            type: .started,
            sessionId: "ordered-start",
            provider: .codex,
            state: .starting,
            timestamp: base
        ))

        XCTAssertEqual(service.sessions[0].startedAt, base)
        XCTAssertEqual(service.sessions[0].state, .running)
    }

    @MainActor
    func testEqualTimestampRoutineEventCannotClearWaitingAttention() {
        let service = AgentActivityService()
        let timestamp = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "attention",
            provider: .codex,
            state: .waitingForUser,
            timestamp: timestamp
        ))
        service.ingest(AgentEvent(
            type: .toolCompleted,
            sessionId: "attention",
            provider: .codex,
            state: .running,
            timestamp: timestamp
        ))

        XCTAssertEqual(service.sessions[0].state, .waitingForUser)
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:attention")
    }

    @MainActor
    func testLaterSessionStartDoesNotRegressProgressedState() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .toolStarted,
            sessionId: "S",
            provider: .codex,
            state: .executingTool,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .started,
            sessionId: "S",
            provider: .codex,
            activity: "Session started",
            state: .starting,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.sessions[0].state, .executingTool)
        XCTAssertEqual(service.sessions[0].currentActivity, "Using tool")
    }

    @MainActor
    func testLaterSessionStartDoesNotClearWaitingAttention() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "S",
            provider: .codex,
            activity: "Needs approval",
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .started,
            sessionId: "S",
            provider: .codex,
            activity: "Session started",
            state: .starting,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.sessions[0].state, .waitingForUser)
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:S")
    }
}
