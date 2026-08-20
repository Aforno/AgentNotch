import AgentsNotchCore
import XCTest

final class AgentPendingReplySessionTests: XCTestCase {
    func testWaitingEventStoresPendingReplyAndLaterActivityClearsIt() {
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
            activity: "Allowed",
            state: .running,
            timestamp: Date().addingTimeInterval(1)
        ))
        XCTAssertEqual(session.state, .running)
        XCTAssertNil(session.pendingReply)
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
}
