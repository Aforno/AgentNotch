import AgentsNotchCore
import XCTest

extension AgentActivityServiceTests {
    @MainActor
    func testAttentionSessionsSortBeforeOtherActiveSessions() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:running",
            provider: .codex,
            activity: "Running tests",
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "claude-code:waiting",
            provider: .claudeCode,
            activity: "Waiting for input",
            state: .waitingForUser
        ))

        XCTAssertEqual(service.sessions.first?.id, "claude-code:waiting")
        XCTAssertEqual(service.attentionCount, 1)
    }

    @MainActor
    func testAttentionQueueIsSortedAndExcludesFailures() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:older",
            provider: .codex,
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .failed,
            sessionId: "failure",
            provider: .grok,
            state: .failed,
            timestamp: base.addingTimeInterval(1)
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "claude-code:newer",
            provider: .claudeCode,
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(2)
        ))

        XCTAssertEqual(service.attentionSessions.map(\.id), ["claude-code:newer", "codex:older"])
        XCTAssertEqual(service.attentionCount, 2)
        XCTAssertEqual(service.attentionSession?.id, "claude-code:newer")
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
            sessionId: "claude-code:permission",
            provider: .claudeCode,
            activity: "Needs command approval",
            state: .waitingForUser
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "claude-code:permission")

        service.ingest(AgentEvent(
            type: .fileChanged,
            sessionId: "unrelated",
            provider: .grok,
            state: .editing
        ))
        XCTAssertEqual(service.attentionEvent?.sessionId, "claude-code:permission")

        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "claude-code:permission",
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
            sessionId: "claude-code:first",
            provider: .claudeCode,
            activity: "Needs command approval",
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "grok:second",
            provider: .grok,
            activity: "Waiting for input",
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "grok:second")

        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "grok:second",
            provider: .grok,
            activity: "Thinking",
            state: .thinking,
            timestamp: base.addingTimeInterval(2)
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "claude-code:first")
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

        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:restored")
        XCTAssertEqual(service.attentionEvent?.activity, "Needs approval")
        XCTAssertEqual(service.attentionEvent?.resolvedState, .waitingForUser)
    }

    @MainActor
    func testRemovingAttentionSessionFallsBackToRemainingWaiter() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:keep",
            provider: .codex,
            activity: "Waiting for input",
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "claude-code:drop",
            provider: .claudeCode,
            activity: "Needs approval",
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.attentionEvent?.sessionId, "claude-code:drop")
        service.removeSession(id: "claude-code:drop")
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:keep")
    }

    @MainActor
    func testRemovingSimulatorBatchClearsItsAttentionAndPreservesRealSessions() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:real",
            provider: .codex,
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:debug-plan",
            provider: .codex,
            state: .waitingForUser
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:debug-child",
            provider: .codex,
            state: .running,
            parentSessionId: "codex:debug-plan"
        ))

        var notifications = 0
        service.onSessionsChanged = { _ in notifications += 1 }
        service.removeSessions(ids: ["codex:debug-plan", "codex:debug-child"])

        XCTAssertEqual(service.sessions.map(\.id), ["codex:real"])
        XCTAssertNil(service.attentionEvent)
        XCTAssertEqual(notifications, 1)
    }

    @MainActor
    func testListCollapsesActiveChildrenIntoParentWorkflowRow() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "grok:workflow",
            provider: .grok,
            task: "Audit and fix",
            state: .running,
            timestamp: base
        ))
        for index in 0..<4 {
            service.ingest(AgentEvent(
                type: .activity,
                sessionId: "grok:worker-\(index)",
                provider: .grok,
                state: .running,
                timestamp: base.addingTimeInterval(TimeInterval(index + 1)),
                parentSessionId: "grok:workflow",
                agentRole: "audit-\(index)"
            ))
        }

        XCTAssertEqual(service.listSessions.map(\.id), ["grok:workflow"])
        XCTAssertEqual(service.children(of: "grok:workflow").count, 4)
        XCTAssertEqual(service.activeGroupCount, 1)
    }

    @MainActor
    func testListSessionsCapsAtThreeIncludingActive() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        for index in 0..<5 {
            service.ingest(AgentEvent(
                type: .completed,
                sessionId: "codex:done-\(index)",
                provider: .codex,
                state: .completed,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:active",
            provider: .codex,
            state: .running,
            timestamp: base.addingTimeInterval(10)
        ))

        XCTAssertEqual(service.listSessions.map(\.id), ["codex:active", "codex:done-4", "codex:done-3"])
        XCTAssertEqual(service.listSessions.count, 3)
    }

    @MainActor
    func testListSessionsAlwaysShowsOnlyThreeMostRecentlyUpdatedGroups() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        for index in 0..<4 {
            service.ingest(AgentEvent(
                type: .activity,
                sessionId: "codex:active-\(index)",
                provider: .codex,
                state: .running,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "claude-code:done",
            provider: .claudeCode,
            state: .completed,
            timestamp: base.addingTimeInterval(20)
        ))

        XCTAssertEqual(service.listSessions.map(\.id), ["claude-code:done", "codex:active-3", "codex:active-2"])
    }

    @MainActor
    func testAttentionGroupRemainsAvailableOutsideThreeRowList() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:waiting-parent",
            provider: .codex,
            state: .waitingForUser,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:waiting-child",
            provider: .codex,
            state: .running,
            timestamp: base,
            parentSessionId: "codex:waiting-parent"
        ))
        for index in 0..<4 {
            service.ingest(AgentEvent(
                type: .completed,
                sessionId: "claude-code:newer-\(index)",
                provider: .claudeCode,
                state: .completed,
                timestamp: base.addingTimeInterval(TimeInterval(index + 1))
            ))
        }

        XCTAssertFalse(service.listSessions.contains { $0.id == "codex:waiting-parent" })
        XCTAssertEqual(service.notchSnapshot.attentionSession?.id, "codex:waiting-parent")
        XCTAssertTrue(service.notchSnapshot.relatedSessions.contains { $0.id == "codex:waiting-parent" })
        XCTAssertTrue(service.notchSnapshot.relatedSessions.contains { $0.id == "codex:waiting-child" })
    }

    @MainActor
    func testNonVisibleHistoryEventDoesNotRepublishNotchSnapshot() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        for index in 0..<4 {
            service.ingest(AgentEvent(
                type: .completed,
                sessionId: "codex:done-\(index)",
                provider: .codex,
                state: .completed,
                timestamp: base.addingTimeInterval(TimeInterval(index))
            ))
        }
        let snapshot = service.notchSnapshot

        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:done-0",
            provider: .codex,
            activity: "Delayed terminal detail",
            state: .completed,
            timestamp: base.addingTimeInterval(-1)
        ))

        XCTAssertEqual(service.notchSnapshot, snapshot)
        XCTAssertEqual(service.sessions.first(where: { $0.id == "codex:done-0" })?.recentEvents.count, 2)
    }

    @MainActor
    func testHousekeepingSessionsAreOmittedFromNotchList() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:memory",
            provider: .codex,
            task: "## Memory Writing Agent: Phase 2 (Consolidation)",
            activity: "Consolidation complete.",
            state: .completed,
            timestamp: base.addingTimeInterval(2)
        ))
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:real",
            provider: .codex,
            task: "Review the changes made",
            activity: "Task completed",
            state: .completed,
            timestamp: base
        ))

        XCTAssertEqual(service.listSessions.map(\.id), ["codex:real"])
        XCTAssertTrue(service.sessions.contains { $0.id == "codex:memory" })
    }

    @MainActor
    func testCommitMessageHelperIsOmittedFromNotchActivity() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .started,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "AgentNotch",
            activity: "Session started",
            state: .starting,
            timestamp: base,
            workingDirectory: "/tmp/AgentNotch"
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Using the supplied git context below, generate a git commit message.",
            activity: "Thinking",
            state: .thinking,
            timestamp: base.addingTimeInterval(1),
            workingDirectory: "/tmp/AgentNotch"
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:real",
            provider: .codex,
            task: "Ship the release",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))

        XCTAssertEqual(service.activeSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.activeGroupCount, 1)
        XCTAssertEqual(service.listSessions.map(\.id), ["codex:real"])
        XCTAssertTrue(service.sessions.contains { $0.id == "codex:commit-helper" })
        XCTAssertTrue(service.attentionSessions.isEmpty)
        XCTAssertNil(service.attentionSession)
        XCTAssertNil(service.attentionEvent)
        XCTAssertEqual(service.attentionCount, 0)
    }

    @MainActor
    func testCommitMessageHelperStaysOmittedAfterOfficialTitle() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Using the supplied git context below, generate a git commit message.",
            activity: "Thinking",
            state: .thinking,
            timestamp: base,
            workingDirectory: "/tmp/AgentNotch"
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Generate commit message",
            activity: "Thinking",
            state: .thinking,
            timestamp: base.addingTimeInterval(1),
            workingDirectory: "/tmp/AgentNotch",
            metadata: ["titleSource": "session"]
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:real",
            provider: .codex,
            task: "Ship the release",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))

        XCTAssertEqual(service.sessions.first { $0.id == "codex:commit-helper" }?.task, "Generate commit message")
        XCTAssertEqual(service.activeSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.listSessions.map(\.id), ["codex:real"])
        XCTAssertTrue(service.sessions.contains { $0.id == "codex:commit-helper" })
    }

    @MainActor
    func testCommitMessageHelperWaitingDoesNotStealAttention() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Using the supplied git context below, generate a git commit message.",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Generate commit message",
            activity: "Needs approval",
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(2),
            metadata: ["titleSource": "session"]
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:real",
            provider: .codex,
            task: "Ship the release",
            activity: "Waiting for input",
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1)
        ))

        XCTAssertEqual(service.attentionSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.attentionSession?.id, "codex:real")
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:real")
        XCTAssertEqual(service.attentionCount, 1)
        XCTAssertFalse(service.listSessions.contains { $0.id == "codex:commit-helper" })
    }

    @MainActor
    func testCommitMessageHelperStaysOmittedAfterEventRingEvictsPrompt() throws {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Using the supplied git context below, generate a git commit message.",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Generate commit message",
            activity: "Thinking",
            state: .thinking,
            timestamp: base.addingTimeInterval(1),
            metadata: ["titleSource": "session"]
        ))
        for offset in 0...AgentSession.recentEventLimit {
            service.ingest(AgentEvent(
                type: .activity,
                sessionId: "codex:commit-helper",
                provider: .codex,
                task: "Generate commit message",
                activity: "Step \(offset)",
                state: .thinking,
                timestamp: base.addingTimeInterval(TimeInterval(offset + 2))
            ))
        }
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:real",
            provider: .codex,
            task: "Ship the release",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))

        let helper = try XCTUnwrap(service.sessions.first { $0.id == "codex:commit-helper" })
        XCTAssertEqual(helper.recentEvents.count, AgentSession.recentEventLimit)
        XCTAssertFalse(helper.recentEvents.contains {
            ($0.task ?? "").localizedCaseInsensitiveContains("using the supplied git context")
        })
        XCTAssertTrue(helper.isInternalHelper)
        XCTAssertEqual(service.activeSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.listSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.activeGroupCount, 1)
    }

    @MainActor
    func testDescendantsOfCommitMessageHelperAreOmittedFromNotchActivity() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper",
            provider: .codex,
            task: "Using the supplied git context below, generate a git commit message.",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:commit-helper-child",
            provider: .codex,
            task: "Write the subject line",
            activity: "Thinking",
            state: .thinking,
            timestamp: base.addingTimeInterval(1),
            parentSessionId: "codex:commit-helper"
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:real",
            provider: .codex,
            task: "Ship the release",
            activity: "Thinking",
            state: .thinking,
            timestamp: base
        ))

        XCTAssertEqual(service.activeSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.listSessions.map(\.id), ["codex:real"])
        XCTAssertEqual(service.activeGroupCount, 1)
        XCTAssertTrue(service.sessions.contains { $0.id == "codex:commit-helper" })
        XCTAssertTrue(service.sessions.contains { $0.id == "codex:commit-helper-child" })
        XCTAssertTrue(service.attentionSessions.isEmpty)
        XCTAssertNil(service.attentionSession)
    }
}
