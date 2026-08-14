@testable import AgentsNotch
import AgentsNotchCore
import Foundation
import XCTest

final class AppRuntimeTests: XCTestCase {
    @MainActor
    func testRuntimeConstructsEveryBuiltInProviderAdapter() {
        let runtime = AppRuntime(monitorProviders: false)

        XCTAssertEqual(
            runtime.providerAdapters.map(\.provider),
            [.codex, .claudeCode, .grok, .geminiCLI, .openCode, .cursor]
        )
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
        XCTAssertFalse(runtime.activity.sessions.contains { $0.id == "expired-live-event" })
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
