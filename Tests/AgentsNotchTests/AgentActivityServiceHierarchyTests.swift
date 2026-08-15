import AgentsNotchCore
import XCTest

extension AgentActivityServiceTests {
    @MainActor
    func testLateChildCannotRemainActiveUnderCompletedParent() {
        let service = AgentActivityService()
        let completedAt = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:parent",
            provider: .codex,
            state: .completed,
            timestamp: completedAt
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:late-child",
            provider: .codex,
            state: .running,
            timestamp: completedAt.addingTimeInterval(1),
            parentSessionId: "codex:parent"
        ))

        let child = service.sessions.first { $0.id == "codex:late-child" }
        XCTAssertEqual(child?.state, .completed)
        XCTAssertFalse(child?.isActive ?? true)
    }

    @MainActor
    func testHierarchyKeepsAttentionSubagentWithParent() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "claude-code:other",
            provider: .claudeCode,
            state: .running,
            timestamp: base.addingTimeInterval(3)
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:parent",
            provider: .codex,
            state: .running,
            timestamp: base
        ))
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:child",
            provider: .codex,
            state: .waitingForUser,
            timestamp: base.addingTimeInterval(1),
            parentSessionId: "codex:parent",
            agentRole: "reviewer"
        ))

        XCTAssertEqual(service.hierarchicalSessions.map(\.id), ["codex:parent", "codex:child", "claude-code:other"])
        XCTAssertEqual(service.children(of: "codex:parent").map(\.id), ["codex:child"])
        XCTAssertEqual(service.parent(of: service.sessions.first { $0.id == "codex:child" }!)?.id, "codex:parent")
    }

    @MainActor
    func testRelationshipCycleStillProducesVisibleActiveGroup() {
        let service = AgentActivityService()
        let base = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:a",
            provider: .codex,
            state: .running,
            timestamp: base,
            parentSessionId: "codex:b"
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:b",
            provider: .codex,
            state: .running,
            timestamp: base.addingTimeInterval(1),
            parentSessionId: "codex:a"
        ))

        XCTAssertEqual(service.activeGroupCount, 1)
        XCTAssertEqual(service.listSessions.count, 1)
        XCTAssertTrue(["codex:a", "codex:b"].contains(service.listSessions[0].id))
    }

    @MainActor
    func testCompletingUnknownParentCompletesWaitingDescendants() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "parent",
                provider: .codex,
                state: .running,
                timestamp: base
            )),
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "child",
                provider: .codex,
                activity: "Needs approval",
                state: .waitingForUser,
                timestamp: base.addingTimeInterval(1),
                parentSessionId: "parent"
            )),
        ])
        service.reconcileUnverifiedActiveSessions(processAlive: { _ in true })
        XCTAssertEqual(service.sessions.first { $0.id == "codex:parent" }?.state, .unknown)
        XCTAssertEqual(service.sessions.first { $0.id == "codex:child" }?.state, .waitingForUser)

        service.completeUnknownSessions()

        XCTAssertEqual(service.sessions.first { $0.id == "codex:parent" }?.state, .completed)
        XCTAssertEqual(service.sessions.first { $0.id == "codex:child" }?.state, .completed)
        XCTAssertNil(service.attentionEvent)
    }

    @MainActor
    func testRestoredTerminalLifecycleCompletesWaitingDescendants() {
        let base = Date(timeIntervalSince1970: 100)
        let service = AgentActivityService(sessions: [
            AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "grok:parent",
                provider: .grok,
                state: .running,
                timestamp: base
            )),
            AgentSession(event: AgentEvent(
                type: .waiting,
                sessionId: "grok:child",
                provider: .grok,
                activity: "Needs approval",
                state: .waitingForUser,
                timestamp: base.addingTimeInterval(1),
                parentSessionId: "grok:parent"
            )),
        ])
        service.reconcileUnverifiedActiveSessions(processAlive: { _ in true })

        service.applyRestoredLifecycle(
            sessionId: "grok:parent",
            state: .completed,
            activity: "Workflow ended",
            at: base.addingTimeInterval(20)
        )

        XCTAssertEqual(service.sessions.first { $0.id == "grok:parent" }?.state, .completed)
        XCTAssertEqual(service.sessions.first { $0.id == "grok:child" }?.state, .completed)
        XCTAssertNil(service.attentionEvent)
    }
}
