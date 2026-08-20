@testable import AgentsNotch
import AgentsNotchCore
import Foundation
import XCTest

final class AppRuntimeTests: XCTestCase {
    @MainActor
    func testRuntimeConstructsEveryBuiltInProviderIntegration() {
        let runtime = AppRuntime(monitorProviders: false)

        XCTAssertEqual(
            runtime.integrations.map(\.provider),
            [.codex, .claudeCode, .grok, .geminiCLI, .openCode, .cursor]
        )
    }

    @MainActor
    func testReplySocketBindFailureDisablesAnswerabilityAndReportsError() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-bind-failure-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let replyURL = root.appendingPathComponent("reply.sock")
        let owner = UnixReplyServer(socketURL: replyURL)
        try owner.start()
        defer { owner.stop() }

        let runtime = AppRuntime(
            persistence: SessionPersistence(fileURL: root.appendingPathComponent("sessions.json")),
            socketURL: root.appendingPathComponent("agent.sock"),
            replySocketURL: replyURL,
            monitorProviders: false,
            answersFromNotch: { true },
            privacyModeEnabled: { false }
        )
        await runtime.start()
        defer { runtime.stop() }

        XCTAssertNotNil(runtime.replySocketError)
        let pending = AgentPendingReply(
            replyId: UUID(),
            kind: .permission,
            prompt: "Allow?",
            grants: [.deny, .allow]
        )
        runtime.activity.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:observer-only",
            provider: .codex,
            state: .waitingForUser,
            pendingReply: pending
        ))
        XCTAssertFalse(runtime.canAnswer(try XCTUnwrap(runtime.activity.session(id: "codex:observer-only"))))
    }

    @MainActor
    func testPrivacyModeInstallsObserverHooksWhenAnswerFromNotchIsEnabled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-privacy-hooks-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundledRelayURL = root.appendingPathComponent("agentsnotch-hook")
        try Data("test relay".utf8).write(to: bundledRelayURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundledRelayURL.path
        )
        let runtime = AppRuntime(
            persistence: SessionPersistence(fileURL: root.appendingPathComponent("sessions.json")),
            socketURL: root.appendingPathComponent("agent.sock"),
            replySocketURL: root.appendingPathComponent("reply.sock"),
            monitorProviders: false,
            providerHomeDirectoryURL: root,
            bundledRelayURL: bundledRelayURL,
            answersFromNotch: { true },
            privacyModeEnabled: { true }
        )
        await runtime.start()
        defer { runtime.stop() }

        let manager = try XCTUnwrap(runtime.integration(for: .claudeCode))
        manager.install()

        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        let hooks = try XCTUnwrap(
            (JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])?["hooks"] as? [String: Any]
        )
        let permission = try XCTUnwrap(
            ((hooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(permission["async"] as? Bool, true)
        XCTAssertEqual(permission["timeout"] as? Int, 5)
        XCTAssertEqual(permission["args"] as? [String], ["--provider", "claude-code"])
        XCTAssertFalse(
            ((permission["args"] as? [String]) ?? []).contains("--answer"),
            "privacy mode must not install blocking --answer hooks"
        )

        let preToolGroups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolGroups.count, 1, "privacy mode must not split PreToolUse into blocking matchers")
        let preTool = try XCTUnwrap((preToolGroups.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(preTool["async"] as? Bool, true)
        XCTAssertEqual(preTool["args"] as? [String], ["--provider", "claude-code"])
    }

    @MainActor
    func testAnswerFromNotchDeliversReplyAndClearsWaitingSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-answer-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let replySocketURL = root.appendingPathComponent("reply.sock")
        let runtime = AppRuntime(
            persistence: SessionPersistence(fileURL: root.appendingPathComponent("sessions.json")),
            socketURL: root.appendingPathComponent("agent.sock"),
            replySocketURL: replySocketURL,
            monitorProviders: false,
            answersFromNotch: { true },
            privacyModeEnabled: { false }
        )
        await runtime.start()
        defer { runtime.stop() }

        let replyId = UUID()
        let helloReady = expectation(description: "hook registered")
        let received = expectation(description: "hook received decision")
        let box = LockedReplyBox()
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = UnixReplyClient.awaitReply(
                id: replyId,
                socketURL: replySocketURL,
                timeoutSeconds: 3,
                afterRegistration: { helloReady.fulfill() }
            )
            box.set(reply)
            received.fulfill()
        }

        await fulfillment(of: [helloReady], timeout: 2)
        let pending = AgentPendingReply(
            replyId: replyId,
            kind: .permission,
            prompt: "Allow this command?",
            detail: "swift test",
            grants: [.deny, .allow]
        )
        runtime.activity.ingest(AgentEvent(
            type: .waiting,
            sessionId: "codex:thr-answer",
            provider: .codex,
            activity: "Needs command approval",
            state: .waitingForUser,
            pendingReply: pending
        ))
        let session = try XCTUnwrap(runtime.activity.session(id: "codex:thr-answer"))
        XCTAssertTrue(runtime.canAnswer(session))
        runtime.answer(session, decision: .allow)
        await fulfillment(of: [received], timeout: 2)

        XCTAssertEqual(box.get()?.decision, .allow)
        XCTAssertEqual(runtime.activity.session(id: session.id)?.state, .running)
        XCTAssertNil(runtime.activity.session(id: session.id)?.pendingReply)
        XCTAssertEqual(runtime.activity.session(id: session.id)?.currentActivity, "Allowed")
    }

    @MainActor
    func testRuntimeEnforcesRetentionAsNewEventsArrive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-runtime-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("agent.sock")
        let bundledRelayURL = root.appendingPathComponent("agentsnotch-hook")
        try Data("test relay".utf8).write(to: bundledRelayURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bundledRelayURL.path
        )
        let runtime = AppRuntime(
            persistence: SessionPersistence(fileURL: root.appendingPathComponent("sessions.json")),
            socketURL: socketURL,
            monitorProviders: false,
            grokHome: root.appendingPathComponent(".grok", isDirectory: true),
            providerHomeDirectoryURL: root,
            bundledRelayURL: bundledRelayURL,
            historyRetentionDays: { 7 }
        )
        let codexIntegration = try XCTUnwrap(runtime.integration(for: .codex))
        codexIntegration.install()
        XCTAssertEqual(codexIntegration.status, .awaitingFirstEvent)
        await runtime.start()
        defer { runtime.stop() }

        try UnixSocketClient.send(AgentEvent(
            type: .completed,
            sessionId: "expired-live-event",
            provider: .codex,
            state: .completed,
            timestamp: Date().addingTimeInterval(-8 * 24 * 60 * 60)
        ), to: socketURL)

        for _ in 0..<30 where runtime.lastEventReceivedAt[.codex] == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(runtime.lastEventReceivedAt[.codex])
        XCTAssertTrue(
            codexIntegration.hasReceivedEvent,
            "genuine events must mark the Codex integration as verified"
        )
        XCTAssertFalse(runtime.activity.sessions.contains { $0.id == "codex:expired-live-event" })
    }

    @MainActor
    func testSelfTestEventsDoNotMasqueradeAsProviderTelemetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-self-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("agent.sock")
        let runtime = AppRuntime(
            persistence: SessionPersistence(fileURL: root.appendingPathComponent("sessions.json")),
            socketURL: socketURL,
            monitorProviders: false
        )
        let codexIntegration = try XCTUnwrap(runtime.integration(for: .codex))
        await runtime.start()
        defer { runtime.stop() }

        try UnixSocketClient.send(AgentEvent(
            type: .activity,
            sessionId: "self-test:codex:fixture",
            provider: .codex,
            state: .running,
            metadata: ["source": "self-test"]
        ), to: socketURL)

        for _ in 0..<30 where runtime.activity.sessions.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(runtime.activity.sessions.contains { $0.id == "self-test:codex:fixture" })
        XCTAssertNil(runtime.lastEventReceivedAt[.codex])
        XCTAssertFalse(
            codexIntegration.hasReceivedEvent,
            "self-test traffic must not promote integration health"
        )
    }
}

private final class LockedReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AgentReply?

    func set(_ reply: AgentReply?) {
        lock.lock()
        value = reply
        lock.unlock()
    }

    func get() -> AgentReply? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
