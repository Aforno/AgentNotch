import AgentsNotchCore
import XCTest

extension AgentActivityServiceTests {
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
    func testColdStartPreservesWaitingAttentionAndMarksUnverifiedRunnersUnknown() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "approval",
                provider: .codex,
                activity: "Needs approval",
                state: .waitingForUser,
                timestamp: base
            )),
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "runner",
                provider: .grok,
                activity: "Running long task",
                state: .running,
                timestamp: base.addingTimeInterval(1)
            )),
        ])

        service.reconcileUnverifiedActiveSessions(processAlive: { _ in true })

        let runner = service.sessions.first { $0.id == "grok:runner" }
        XCTAssertEqual(service.sessions.first { $0.id == "codex:approval" }?.state, .waitingForUser)
        XCTAssertEqual(runner?.state, .unknown)
        XCTAssertEqual(runner?.currentActivity, "Running long task")
        XCTAssertNil(runner?.completedAt)
        XCTAssertTrue(runner?.isActive ?? false)
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:approval")
    }

    @MainActor
    func testColdStartCompletesRunnersWhoseOriginProcessIsDead() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "dead-process",
                provider: .codex,
                activity: "Halfway through",
                state: .executingTool,
                timestamp: base,
                origin: AgentOrigin(processIdentifier: 42_424)
            )),
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "live-process",
                provider: .claudeCode,
                activity: "Still going",
                state: .running,
                timestamp: base,
                origin: AgentOrigin(processIdentifier: 99_999)
            )),
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "no-origin",
                provider: .geminiCLI,
                activity: "No pid",
                state: .thinking,
                timestamp: base
            )),
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "dead-waiter",
                provider: .cursor,
                activity: "Needs approval",
                state: .waitingForUser,
                timestamp: base,
                origin: AgentOrigin(processIdentifier: 42_425)
            )),
        ])

        service.reconcileUnverifiedActiveSessions(processAlive: { $0 == 99_999 })

        XCTAssertEqual(service.sessions.first { $0.id == "codex:dead-process" }?.state, .completed)
        XCTAssertEqual(service.sessions.first { $0.id == "claude-code:live-process" }?.state, .unknown)
        XCTAssertEqual(service.sessions.first { $0.id == "gemini-cli:no-origin" }?.state, .unknown)
        XCTAssertEqual(service.sessions.first { $0.id == "cursor:dead-waiter" }?.state, .completed)
        XCTAssertNil(service.attentionEvent)
    }

    @MainActor
    func testColdStartCompletesWaiterWhenOriginPIDWasReused() {
        let recordedStart = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "recycled-pid",
                provider: .codex,
                state: .waitingForUser,
                timestamp: recordedStart,
                origin: AgentOrigin(
                    processIdentifier: 42_424,
                    processStartedAt: recordedStart
                )
            )),
        ])

        service.reconcileUnverifiedActiveSessions(
            processAlive: { _ in true },
            processStartedAt: { _ in recordedStart.addingTimeInterval(10) }
        )

        XCTAssertEqual(service.sessions.first?.state, .completed)
        XCTAssertNil(service.attentionEvent)
    }

    @MainActor
    func testColdStartPreservesLegacyWaiterWhenProcessIsAlive() {
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "legacy-waiter",
                provider: .codex,
                state: .waitingForUser,
                origin: AgentOrigin(processIdentifier: 42_424)
            )),
        ])

        service.reconcileUnverifiedActiveSessions(processAlive: { _ in true })

        XCTAssertEqual(service.sessions.first?.state, .waitingForUser)
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:legacy-waiter")
    }

    @MainActor
    func testColdStartPreservesWaiterWhenProcessIdentityMatches() {
        let recordedStart = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "live-waiter",
                provider: .codex,
                state: .waitingForUser,
                origin: AgentOrigin(
                    processIdentifier: 42_424,
                    processStartedAt: recordedStart
                )
            )),
        ])

        service.reconcileUnverifiedActiveSessions(
            processAlive: { _ in true },
            processStartedAt: { _ in recordedStart }
        )

        XCTAssertEqual(service.sessions.first?.state, .waitingForUser)
        XCTAssertEqual(service.attentionEvent?.sessionId, "codex:live-waiter")
    }

    @MainActor
    func testUnknownSessionsCompleteAfterGraceAndResumeOnLiveEvent() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "orphan",
                provider: .codex,
                activity: "Before restart",
                state: .running,
                timestamp: base
            )),
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "still-live",
                provider: .claudeCode,
                activity: "Before restart",
                state: .running,
                timestamp: base
            )),
        ])
        service.reconcileUnverifiedActiveSessions(processAlive: { _ in true })

        service.ingest(AgentEvent(
            type: .toolStarted,
            sessionId: "claude-code:still-live",
            provider: .claudeCode,
            activity: "Running tests",
            state: .executingTool,
            timestamp: base.addingTimeInterval(5)
        ))
        service.completeUnknownSessions()

        XCTAssertEqual(service.sessions.first { $0.id == "codex:orphan" }?.state, .completed)
        XCTAssertEqual(service.sessions.first { $0.id == "claude-code:still-live" }?.state, .executingTool)
        XCTAssertEqual(service.sessions.first { $0.id == "claude-code:still-live" }?.currentActivity, "Running tests")
    }

    @MainActor
    func testRestoredLifecycleEvidenceResolvesUnknownGrokSession() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "grok:workflow",
                provider: .grok,
                activity: "Workflow · Audit",
                state: .running,
                timestamp: base
            )),
        ])
        service.reconcileUnverifiedActiveSessions(processAlive: { _ in true })
        XCTAssertEqual(service.sessions.first?.state, .unknown)

        service.applyRestoredLifecycle(
            sessionId: "grok:workflow",
            state: .completed,
            activity: "Workflow · Confirm",
            at: base.addingTimeInterval(20)
        )

        XCTAssertEqual(service.sessions.first?.state, .completed)
        XCTAssertEqual(service.sessions.first?.completedAt, base.addingTimeInterval(20))
    }

    @MainActor
    func testProviderCollisionCreatesSeparateCanonicalSession() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:shared-native-id",
            provider: .codex,
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "grok:shared-native-id",
            provider: .grok,
            state: .running
        ))

        XCTAssertEqual(service.sessions.count, 2)
        XCTAssertEqual(Set(service.sessions.map(\.id)), ["codex:shared-native-id", "grok:shared-native-id"])
        XCTAssertEqual(Set(service.sessions.map(\.provider)), [.codex, .grok])
    }

    @MainActor
    func testRestoreCanonicalizesCrossProviderAndDuplicateIdentities() {
        let base = Date(timeIntervalSince1970: 100)
        let codexOlder = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "shared",
            provider: .codex,
            task: "old",
            state: .running,
            timestamp: base
        ))
        let codexNewer = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "shared",
            provider: .codex,
            task: "new",
            state: .running,
            timestamp: base.addingTimeInterval(2)
        ))
        let grok = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "shared",
            provider: .grok,
            state: .running,
            timestamp: base.addingTimeInterval(1)
        ))

        let service = AgentActivityService(sessions: [codexOlder, codexNewer, grok])

        XCTAssertEqual(service.sessions.count, 2)
        XCTAssertEqual(Set(service.sessions.map(\.id)), ["codex:shared", "grok:shared"])
        XCTAssertEqual(service.sessions.first(where: { $0.provider == .codex })?.task, "new")
    }

    @MainActor
    func testChildAfterCrossProviderCollisionAttachesToRenamedParent() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:shared",
            provider: .codex,
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "grok:shared",
            provider: .grok,
            state: .running
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "grok:child",
            provider: .grok,
            state: .running,
            parentSessionId: "grok:shared"
        ))

        XCTAssertEqual(service.sessions.first { $0.id == "grok:child" }?.parentSessionId, "grok:shared")

        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "grok:shared",
            provider: .grok,
            state: .completed
        ))

        XCTAssertEqual(service.sessions.first { $0.id == "grok:child" }?.state, .completed)
    }

    @MainActor
    func testPrefixedSameProviderEventMergesIntoExistingBareSession() {
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "abc",
                provider: .codex,
                state: .running
            )),
        ])
        service.ingest(AgentEvent(
            type: .fileChanged,
            sessionId: "codex:abc",
            provider: .codex,
            activity: "Editing App.swift",
            state: .editing
        ))

        XCTAssertEqual(service.sessions.count, 1)
        XCTAssertEqual(service.sessions[0].id, "codex:abc")
        XCTAssertEqual(service.sessions[0].state, .editing)
        XCTAssertEqual(service.sessions[0].currentActivity, "Editing App.swift")
    }

    @MainActor
    func testCanonicalEventPrefersExactRowOverPersistedBareDuplicate() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "abc",
                provider: .codex,
                state: .running,
                timestamp: base
            )),
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "codex:abc",
                provider: .codex,
                activity: "Needs approval",
                state: .waitingForUser,
                timestamp: base.addingTimeInterval(1)
            )),
        ])

        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:abc",
            provider: .codex,
            state: .completed,
            timestamp: base.addingTimeInterval(2)
        ))

        XCTAssertEqual(service.sessions.count, 1)
        XCTAssertEqual(service.session(id: "codex:abc")?.state, .completed)
        XCTAssertNil(service.session(id: "abc"))
        XCTAssertNil(service.attentionEvent)
    }

    @MainActor
    func testReconcileRestoredWorkflowDoesNotCreateMissingActiveSession() {
        let service = AgentActivityService()
        service.reconcileRestoredWorkflow(AgentEvent(
            protocolVersion: 1,
            type: .activity,
            sessionId: "grok:parent",
            provider: .grok,
            state: .running,
            workflowUpdate: AgentWorkflowUpdate(id: "wf", title: "Audit", status: .running)
        ))

        XCTAssertTrue(service.sessions.isEmpty)
    }
}
