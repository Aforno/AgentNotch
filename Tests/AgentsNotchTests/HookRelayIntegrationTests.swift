@testable import AgentsNotchCore
import Foundation
import XCTest

/// Spawns the real relay binary against temporary sockets and exercises the
/// most fragile boundary in the product: hook process → event socket + reply
/// socket → decision back to the blocked hook, plus the fail-open path when
/// the app is not listening.
final class HookRelayIntegrationTests: XCTestCase {
    private func locateHookBinary() throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/AgentsNotchTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
        guard FileManager.default.fileExists(atPath: buildRoot.path) else {
            throw XCTSkip(".build directory missing; run swift build first")
        }

        var candidates: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: nil
        )
        let fileManager = FileManager.default
        while let object = enumerator?.nextObject() {
            guard let url = object as? URL,
                  url.lastPathComponent == "AgentsNotchHook",
                  // Skip release DWARF images inside .dSYM bundles.
                  !url.path.contains(".dSYM/"),
                  fileManager.isExecutableFile(atPath: url.path)
            else { continue }
            candidates.append(url)
        }
        // Prefer the plain-debug binary.
        guard let binary = candidates.first { $0.path.contains("/debug/") } ?? candidates.first else {
            throw XCTSkip("AgentsNotchHook executable not found under .build")
        }
        return binary
    }

    private func makeTemporaryRoot(_ label: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-relay-\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private static func spawnHook(
        binary: URL,
        arguments: [String],
        payload: Data,
        environment extraEnvironment: [String: String] = [:]
    ) throws -> (process: Process, stdoutBox: DataBox, stderrBox: DataBox, exited: XCTestExpectation) {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GROK_HOOK_EVENT")
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stdoutBox.append(chunk) }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrBox.append(chunk) }
        }

        let exited = XCTestExpectation(description: "hook exited")
        process.terminationHandler = { _ in exited.fulfill() }
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: payload)
        try? stdin.fileHandleForWriting.close()

        return (process, stdoutBox, stderrBox, exited)
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        func append(_ data: Data) {
            lock.lock()
            storage.append(data)
            lock.unlock()
        }

        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
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

        let hooks = try HookRelayIntegrationTests.spawnHook(
            binary: binary,
            arguments: [
                binary.path,
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
        XCTAssertEqual(hooks.process.terminationStatus, 0)

        let output = String(decoding: hooks.stdoutBox.value, as: UTF8.self)
        XCTAssertTrue(output.contains("PermissionRequest"), "decision must address the PermissionRequest hook, got \(output)")
        XCTAssertTrue(output.contains("allow"), "submitted allow decision must reach the hook stdout")
    }

    func testHookFailsOpenWhenAppIsNotListening() async throws {
        let binary = try locateHookBinary()
        let root = try makeTemporaryRoot("failopen")
        let eventSocket = root.appendingPathComponent("agent.sock")

        let hooks = try HookRelayIntegrationTests.spawnHook(
            binary: binary,
            arguments: [
                binary.path,
                "--provider", "claude-code",
                "--socket", eventSocket.path,
                "--reply-socket", root.appendingPathComponent("reply.sock").path,
                "--answer",
            ],
            payload: permissionPayload(sessionID: "relay-failopen")
        )

        await fulfillment(of: [hooks.exited], timeout: 15)
        XCTAssertEqual(hooks.process.terminationStatus, 0, "observer failures must never fail the provider hook")
        XCTAssertTrue(
            hooks.stdoutBox.value.isEmpty,
            "Claude passive runs must keep stdout empty even in answer mode"
        )
    }

    func testUnknownProviderWarningIsVisibleOnStderr() async throws {
        let binary = try locateHookBinary()
        let root = try makeTemporaryRoot("unknown-provider")

        let hooks = try HookRelayIntegrationTests.spawnHook(
            binary: binary,
            arguments: [binary.path, "--provider", "not-a-provider", "--socket", root.appendingPathComponent("agent.sock").path],
            payload: permissionPayload(sessionID: "relay-warn")
        )
        await fulfillment(of: [hooks.exited], timeout: 15)
        XCTAssertEqual(hooks.process.terminationStatus, 0)

        let stderr = String(decoding: hooks.stderrBox.value, as: UTF8.self)
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
