import AgentsNotchCore
import XCTest

final class AgentPendingReplySessionTests: XCTestCase {
    func testRoutineActivityKeepsPendingWaitUntilSocketLivenessReconciliation() {
        let replyId = UUID()
        var session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "codex:thr",
            provider: .codex,
            activity: "Needs command approval",
            state: .waitingForUser,
            pendingReply: AgentPendingReply(
                replyId: replyId,
                kind: .permission,
                prompt: "Allow this command?",
                detail: "swift test",
                grants: [.deny, .allow]
            )
        ))
        XCTAssertEqual(session.pendingReply?.replyId, replyId)

        _ = session.apply(AgentEvent(
            type: .activity,
            sessionId: "codex:thr",
            provider: .codex,
            activity: "Another tool finished",
            state: .running,
            timestamp: Date().addingTimeInterval(1)
        ))
        XCTAssertEqual(session.state, .waitingForUser)
        XCTAssertEqual(session.currentActivity, "Needs command approval")
        XCTAssertEqual(session.pendingReply?.replyId, replyId)
        session.retainPendingReplies { _ in false }
        XCTAssertNil(session.pendingReply)
        _ = session.apply(AgentEvent(
            type: .toolCompleted,
            sessionId: session.id,
            provider: session.provider,
            timestamp: Date().addingTimeInterval(2)
        ))
        XCTAssertEqual(session.state, .running)
    }

    @MainActor
    func testAnsweringResolvesThatReplyWithoutWaitingForSocketReconciliation() {
        let answered = UUID()
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:thr",
            provider: .codex,
            activity: "Needs command approval",
            state: .waitingForUser,
            pendingReply: AgentPendingReply(
                replyId: answered,
                kind: .permission,
                prompt: "Allow this command?",
                detail: "swift test",
                grants: [.deny, .allow]
            )
        ))
        XCTAssertEqual(service.session(id: "codex:thr")?.pendingReply?.replyId, answered)

        service.resolvePendingReply(answered, in: "codex:thr")

        XCTAssertNil(service.session(id: "codex:thr")?.pendingReply)
        XCTAssertEqual(service.session(id: "codex:thr")?.pendingReplies.count, 0)
    }

    @MainActor
    func testReorderedPendingReplyStillPromotesAttention() {
        let service = AgentActivityService()
        let toolTime = Date(timeIntervalSince1970: 101)
        service.ingest(AgentEvent(
            type: .toolCompleted,
            sessionId: "codex:concurrent",
            provider: .codex,
            timestamp: toolTime
        ))
        let pending = AgentPendingReply(
            replyId: UUID(), kind: .permission, prompt: "Allow?", grants: [.deny, .allow]
        )
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:concurrent",
            provider: .codex,
            activity: "Needs command approval",
            timestamp: toolTime.addingTimeInterval(-1),
            pendingReply: pending
        ))

        XCTAssertEqual(service.attentionCount, 1)
        XCTAssertEqual(service.attentionSession?.pendingReply, pending)
        XCTAssertEqual(service.attentionSession?.currentActivity, "Needs command approval")
        XCTAssertEqual(service.attentionSession?.updatedAt, toolTime)
    }

    @MainActor
    func testResolvingOneReplyFallsBackToTheOtherStillWaitingPrompt() {
        let answered = UUID()
        let other = UUID()
        let service = AgentActivityService()
        for replyId in [answered, other] {
            service.ingest(AgentEvent(
                type: .waiting,
                sessionId: "codex:thr",
                provider: .codex,
                activity: "Needs command approval",
                state: .waitingForUser,
                pendingReply: AgentPendingReply(
                    replyId: replyId,
                    kind: .permission,
                    prompt: "Allow this command?",
                    grants: [.deny, .allow]
                )
            ))
        }

        service.resolvePendingReply(answered, in: "codex:thr")

        XCTAssertEqual(service.session(id: "codex:thr")?.pendingReply?.replyId, other)
        XCTAssertEqual(service.session(id: "codex:thr")?.pendingReplies.count, 1)
    }

    @MainActor
    func testRestoredSessionsDropPendingReply() {
        let session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "codex:thr",
            provider: .codex,
            activity: "Needs command approval",
            state: .waitingForUser,
            pendingReply: AgentPendingReply(
                replyId: UUID(),
                kind: .permission,
                prompt: "Allow this command?",
                grants: [.deny, .allow]
            )
        ))
        let service = AgentActivityService(sessions: [session])
        XCTAssertEqual(service.session(id: "codex:thr")?.state, .waitingForUser)
        XCTAssertNil(service.session(id: "codex:thr")?.pendingReply)
    }

    func testSimultaneousWaitsRemainKeyedByReplyId() {
        let first = AgentPendingReply(
            replyId: UUID(),
            kind: .permission,
            prompt: "First",
            grants: [.deny, .allow]
        )
        let second = AgentPendingReply(
            replyId: UUID(),
            kind: .permission,
            prompt: "Second",
            grants: [.deny, .allow]
        )
        var session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "codex:concurrent",
            provider: .codex,
            state: .waitingForUser,
            pendingReply: first
        ))
        _ = session.apply(AgentEvent(
            type: .waiting,
            sessionId: "codex:concurrent",
            provider: .codex,
            state: .waitingForUser,
            timestamp: Date().addingTimeInterval(1),
            pendingReply: second
        ))

        XCTAssertEqual(Set(session.pendingReplies.map(\.replyId)), [first.replyId, second.replyId])
        session.retainPendingReplies { $0 == first.replyId }
        XCTAssertEqual(session.pendingReply?.replyId, first.replyId)
    }

    @MainActor
    func testEqualTimestampWaitingReplyRefreshesIndexedSessionAndNotchSnapshot() {
        let service = AgentActivityService()
        let timestamp = Date(timeIntervalSince1970: 100)
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:reply",
            provider: .codex,
            state: .waitingForUser,
            timestamp: timestamp
        ))

        let reply = AgentPendingReply(
            replyId: UUID(),
            kind: .permission,
            prompt: "Allow this command?",
            grants: [.deny, .allow]
        )
        service.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:reply",
            provider: .codex,
            state: .waitingForUser,
            timestamp: timestamp,
            pendingReply: reply
        ))

        XCTAssertEqual(service.sessions.first?.pendingReply, reply)
        XCTAssertEqual(service.session(id: "codex:reply")?.pendingReply, reply)
        XCTAssertEqual(service.notchSnapshot.attentionSession?.pendingReply, reply)
    }
}
