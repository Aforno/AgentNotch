import AgentsNotchCore
import Darwin
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
        defer {
            server.stop()
            try? FileManager.default.removeItem(atPath: socketURL.path + ".lock")
        }

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

    func testOversizedConnectionDoesNotDeliverValidLeadingEvent() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-\(UUID().uuidString.prefix(8)).sock")
        let received = expectation(description: "No event delivered from oversized connection")
        received.isInverted = true
        let server = UnixSocketServer(socketURL: socketURL, maximumPayloadBytes: 1_024) { _ in
            received.fulfill()
        }
        try server.start()
        defer {
            server.stop()
            try? FileManager.default.removeItem(atPath: socketURL.path + ".lock")
        }

        var payload = try JSONEncoder.agentsNotch.encode(AgentEvent(
            type: .activity,
            sessionId: "must-not-arrive",
            provider: .codex,
            state: .running
        ))
        payload.append(0x0A)
        payload.append(Data(repeating: 0x20, count: 2_048))
        try sendRaw(payload, to: socketURL)

        wait(for: [received], timeout: 0.35)
    }

    func testSecondServerCannotReplaceLiveSocket() throws {
        let socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-\(UUID().uuidString.prefix(8)).sock")
        let first = UnixSocketServer(socketURL: socketURL) { _ in }
        let second = UnixSocketServer(socketURL: socketURL) { _ in }
        try first.start()
        defer {
            second.stop()
            first.stop()
            try? FileManager.default.removeItem(atPath: socketURL.path + ".lock")
        }

        XCTAssertThrowsError(try second.start()) { error in
            guard case AgentSocketError.alreadyInUse = error else {
                return XCTFail("Expected alreadyInUse, got \(error)")
            }
        }
    }

    private func sendRaw(_ data: Data, to socketURL: URL) throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.systemCall("socket", errno) }
        defer { Darwin.close(fd) }
        var noSigPipe: Int32 = 1
        guard setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw AgentSocketError.systemCall("setsockopt(SO_NOSIGPIPE)", errno)
        }

        var path = sockaddr_un()
        path.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketURL.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: path.sun_path) else {
            throw AgentSocketError.pathTooLong
        }
        withUnsafeMutablePointer(to: &path.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count) { destination in
                for index in bytes.indices {
                    destination[index] = bytes[index]
                }
            }
        }
        let connected = withUnsafePointer(to: &path) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw AgentSocketError.systemCall("connect", errno) }

        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if written < 0, errno == EPIPE { return }
                guard written > 0 else { throw AgentSocketError.systemCall("write", errno) }
                offset += written
            }
        }
        _ = Darwin.shutdown(fd, SHUT_WR)
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
