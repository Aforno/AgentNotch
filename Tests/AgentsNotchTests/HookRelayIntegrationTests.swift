@testable import AgentsNotchCore
import Foundation
import XCTest

/// Spawns the real relay binary against temporary sockets and exercises the
/// most fragile boundary in the product: hook process → event socket + reply
/// socket → decision back to the blocked hook, plus the fail-open path when
/// the app is not listening.
final class HookRelayIntegrationTests: XCTestCase {
    /// Finds the SwiftPM relay beside the test bundle in the active configuration.
    private func locateHookBinary() throws -> URL {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
            .appendingPathComponent("AgentsNotchHook")
        return try XCTUnwrap(
            FileManager.default.isExecutableFile(atPath: binary.path) ? binary : nil,
            "Missing relay for this test configuration: \(binary.path)"
        )
    }

    private func makeTemporaryRoot(_ label: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-relay-\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func spawnHook(
        binary: URL,
        arguments: [String],
        payload: Data
    ) throws -> (process: Process, stdout: FileHandle, stderr: FileHandle, exited: XCTestExpectation) {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GROK_HOOK_EVENT")
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let exited = XCTestExpectation(description: "hook exited")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        addTeardownBlock {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? stdout.fileHandleForReading.close()
            try? stderr.fileHandleForReading.close()
        }
        defer { try? stdin.fileHandleForWriting.close() }
        try stdin.fileHandleForWriting.write(contentsOf: payload)

        return (process, stdout.fileHandleForReading, stderr.fileHandleForReading, exited)
    }

    private func permissionPayload(sessionID: String) -> Data {
        Data("""
        {"session_id":"\(sessionID)","cwd":"/tmp/agentnotch-demo","hook_event_name":"PermissionRequest","tool_name":"shell","tool_input":{"command":"cargo test"}}
        """.utf8)
    }

    func testAnswerModeDeliversDecisionToBlockedHook() async throws {
        let binary = try locateHookBinary()
        let root = try makeTemporaryRoot("answer")
        let eventSocket = root.appendingPathComponent("agent.sock")
        let replySocket = root.appendingPathComponent("reply.sock")

        let eventReceived = expectation(description: "waiting event received")
        let receivedEventBox = EventBox()
        let server = UnixSocketServer(socketURL: eventSocket) { event in
            if event.type == .waiting && event.pendingReply != nil {
                receivedEventBox.store(event)
                eventReceived.fulfill()
            }
        }
        try server.start()
        defer { server.stop() }

        let replyServer = UnixReplyServer(socketURL: replySocket)
        try replyServer.start()
        defer { replyServer.stop() }

        let hooks = try spawnHook(
            binary: binary,
            arguments: [
                "--provider", "codex",
                "--socket", eventSocket.path,
                "--reply-socket", replySocket.path,
                "--answer",
            ],
            payload: permissionPayload(sessionID: "relay-answer")
        )

        await fulfillment(of: [eventReceived], timeout: 10)
        let waitingEvent = try XCTUnwrap(receivedEventBox.load())
        XCTAssertEqual(waitingEvent.sessionId, "codex:relay-answer")
        XCTAssertEqual(waitingEvent.provider, .codex)

        let pending = try XCTUnwrap(waitingEvent.pendingReply)
        XCTAssertEqual(pending.kind, .permission)
        XCTAssertTrue(pending.allowsAllow)
        XCTAssertTrue(replyServer.isPending(pending.replyId), "hook must be registered before a reply is submitted")

        let delivered = replyServer.submit(AgentReply(replyId: pending.replyId, decision: .allow))
        XCTAssertTrue(delivered)

        await fulfillment(of: [hooks.exited], timeout: 10)
        guard !hooks.process.isRunning else { return XCTFail("Relay did not exit before the timeout") }
        XCTAssertEqual(hooks.process.terminationStatus, 0)

        let output = try XCTUnwrap(
            JSONSerialization.jsonObject(with: hooks.stdout.readDataToEndOfFile()) as? [String: Any]
        )
        let hookOutput = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(hookOutput["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(hookOutput["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
    }

    func testHookFailsOpenWhenAppIsNotListening() async throws {
        let binary = try locateHookBinary()
        let root = try makeTemporaryRoot("failopen")
        let eventSocket = root.appendingPathComponent("agent.sock")

        let hooks = try spawnHook(
            binary: binary,
            arguments: [
                "--provider", "claude-code",
                "--socket", eventSocket.path,
                "--reply-socket", root.appendingPathComponent("reply.sock").path,
                "--answer",
            ],
            payload: permissionPayload(sessionID: "relay-failopen")
        )

        await fulfillment(of: [hooks.exited], timeout: 15)
        guard !hooks.process.isRunning else { return XCTFail("Relay did not exit before the timeout") }
        XCTAssertEqual(hooks.process.terminationStatus, 0, "observer failures must never fail the provider hook")
        XCTAssertTrue(
            hooks.stdout.readDataToEndOfFile().isEmpty,
            "Claude passive runs must keep stdout empty even in answer mode"
        )
    }

    func testAntigravityEventFlagMapsPayloadWithoutHookEventName() async throws {
        let binary = try locateHookBinary()
        let root = try makeTemporaryRoot("antigravity")
        let eventSocket = root.appendingPathComponent("agent.sock")

        let eventReceived = expectation(description: "antigravity tool event received")
        let receivedEventBox = EventBox()
        let server = UnixSocketServer(socketURL: eventSocket) { event in
            if event.type == .toolStarted {
                receivedEventBox.store(event)
                eventReceived.fulfill()
            }
        }
        try server.start()
        defer { server.stop() }

        let payload = Data("""
        {"conversationId":"agy-relay","workspacePaths":["/tmp/AgentsNotch"],"toolCall":{"name":"run_command","args":{"CommandLine":"swift test"}}}
        """.utf8)
        let hooks = try spawnHook(
            binary: binary,
            arguments: [
                "--provider", "antigravity",
                "--event", "PreToolUse",
                "--socket", eventSocket.path,
            ],
            payload: payload
        )

        await fulfillment(of: [eventReceived, hooks.exited], timeout: 10)
        guard !hooks.process.isRunning else { return XCTFail("Relay did not exit before the timeout") }
        XCTAssertEqual(hooks.process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: hooks.stdout.readDataToEndOfFile(), as: UTF8.self), "{}\n")
        let event = try XCTUnwrap(receivedEventBox.load())
        XCTAssertEqual(event.sessionId, "antigravity:agy-relay")
        XCTAssertEqual(event.provider, .antigravity)
        XCTAssertEqual(event.activity, "Running swift test")
    }

    func testUnknownProviderWarningIsVisibleOnStderr() async throws {
        let binary = try locateHookBinary()
        let root = try makeTemporaryRoot("unknown-provider")

        let hooks = try spawnHook(
            binary: binary,
            arguments: ["--provider", "not-a-provider", "--socket", root.appendingPathComponent("agent.sock").path],
            payload: permissionPayload(sessionID: "relay-warn")
        )
        await fulfillment(of: [hooks.exited], timeout: 15)
        guard !hooks.process.isRunning else { return XCTFail("Relay did not exit before the timeout") }
        XCTAssertEqual(hooks.process.terminationStatus, 0)

        let stderr = String(decoding: hooks.stderr.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertTrue(stderr.contains("unknown --provider"), "misconfiguration must be diagnosable, got \(stderr)")
        XCTAssertTrue(stderr.contains("not-a-provider"))
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var event: AgentEvent?

    func store(_ value: AgentEvent) {
        lock.lock()
        event = value
        lock.unlock()
    }

    func load() -> AgentEvent? {
        lock.lock()
        defer { lock.unlock() }
        return event
    }
}
