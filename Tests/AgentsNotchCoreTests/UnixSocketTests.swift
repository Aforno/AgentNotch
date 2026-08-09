import AgentsNotchCore
import Foundation
import XCTest

final class UnixSocketTests: XCTestCase {
    func testEventRoundTripsOverPrivateUnixSocket() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-\(UUID().uuidString.prefix(8)).sock")
        let received = expectation(description: "Event received")
        let box = LockedEventBox()
        let server = UnixSocketServer(socketURL: socketURL) { event in
            box.set(event)
            received.fulfill()
        }
        try server.start()
        defer { server.stop() }

        let sent = AgentEvent(
            type: .activity,
            sessionId: "round-trip",
            provider: .codex,
            activity: "Running tests",
            state: .running,
            parentSessionId: "parent",
            agentRole: "reviewer",
            plan: AgentPlan(
                title: "Release readiness",
                explanation: "Verify the complete event survives transport.",
                steps: [
                    AgentStep(id: "verify", title: "Run tests", status: .inProgress),
                ]
            ),
            workflowUpdate: AgentWorkflowUpdate(
                id: "release",
                title: "Release",
                status: .running
            )
        )
        try UnixSocketClient.send(sent, to: socketURL)
        wait(for: [received], timeout: 2)

        let actual = try XCTUnwrap(box.get())
        XCTAssertEqual(actual.id, sent.id)
        XCTAssertEqual(actual.sessionId, sent.sessionId)
        XCTAssertEqual(actual.activity, sent.activity)
        XCTAssertEqual(actual.state, sent.state)
        XCTAssertEqual(actual.parentSessionId, sent.parentSessionId)
        XCTAssertEqual(actual.agentRole, sent.agentRole)
        XCTAssertEqual(actual.plan?.title, sent.plan?.title)
        XCTAssertEqual(actual.plan?.explanation, sent.plan?.explanation)
        XCTAssertEqual(actual.plan?.steps, sent.plan?.steps)
        XCTAssertLessThan(abs(try XCTUnwrap(actual.plan?.updatedAt).timeIntervalSince(
            try XCTUnwrap(sent.plan?.updatedAt)
        )), 0.001)
        XCTAssertEqual(actual.workflowUpdate, sent.workflowUpdate)
        XCTAssertLessThan(abs(actual.timestamp.timeIntervalSince(sent.timestamp)), 0.001)
    }
}

private final class LockedEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AgentEvent?

    func set(_ event: AgentEvent) {
        lock.lock()
        value = event
        lock.unlock()
    }

    func get() -> AgentEvent? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
