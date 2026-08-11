@testable import AgentsNotch
import AgentsNotchCore
import Foundation
import XCTest

final class RoadmapFeatureTests: XCTestCase {
    @MainActor
    func testRuntimeConstructsEveryBuiltInProviderAdapter() {
        let runtime = AppRuntime(monitorProviders: false)

        XCTAssertEqual(
            runtime.providerAdapters.map(\.provider),
            [.codex, .claudeCode, .grok, .geminiCLI, .openCode, .cursor]
        )
    }

    func testOriginMetadataRoundTripsThroughSessionPersistenceModel() throws {
        let origin = AgentOrigin(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 42,
            terminalProgram: "Apple_Terminal",
            terminalSessionIdentifier: "session-1",
            tty: "/dev/ttys001"
        )
        let session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "origin",
            provider: .codex,
            state: .waitingForUser,
            origin: origin
        ))

        let data = try JSONEncoder.agentsNotch.encode(session)
        let decoded = try JSONDecoder.agentsNotch.decode(AgentSession.self, from: data)

        XCTAssertEqual(decoded.origin, origin)
    }

    func testAttentionQueueIsSortedAndExcludesFailures() async {
        await MainActor.run {
            let service = AgentActivityService()
            let base = Date(timeIntervalSince1970: 100)
            service.ingest(AgentEvent(
                type: .waiting,
                sessionId: "older",
                provider: .codex,
                state: .waitingForUser,
                timestamp: base
            ))
            service.ingest(AgentEvent(
                type: .failed,
                sessionId: "failure",
                provider: .grok,
                state: .failed,
                timestamp: base.addingTimeInterval(1)
            ))
            service.ingest(AgentEvent(
                type: .waiting,
                sessionId: "newer",
                provider: .claudeCode,
                state: .waitingForUser,
                timestamp: base.addingTimeInterval(2)
            ))

            XCTAssertEqual(service.attentionSessions.map(\.id), ["newer", "older"])
            XCTAssertEqual(service.attentionCount, 2)
            XCTAssertEqual(service.attentionSession?.id, "newer")
        }
    }

    func testDayBasedHistoryRetentionHasNoHiddenSessionCountCap() async {
        await MainActor.run {
            let service = AgentActivityService()
            let base = Date().addingTimeInterval(-60)
            for index in 0..<25 {
                service.ingest(AgentEvent(
                    type: .completed,
                    sessionId: "completed-\(index)",
                    provider: .codex,
                    state: .completed,
                    timestamp: base.addingTimeInterval(TimeInterval(index))
                ))
            }

            service.pruneCompleted(olderThan: 7 * 24 * 60 * 60)

            XCTAssertEqual(service.recentSessions.count, 25)
        }
    }

    @MainActor
    func testRuntimeEnforcesRetentionAsNewEventsArrive() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-roadmap-\(UUID().uuidString.prefix(8))", isDirectory: true)
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
        runtime.codexIntegration.install()
        XCTAssertEqual(runtime.codexIntegration.status, .awaitingFirstEvent)
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
            runtime.codexIntegration.hasReceivedEvent,
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
            runtime.codexIntegration.hasReceivedEvent,
            "self-test traffic must not promote integration health"
        )
    }

    func testGeminiLifecycleAliasesMapToProviderNeutralEvents() throws {
        let beforeAgent = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "BeforeAgent",
          "prompt": "Add a Gemini integration"
        }
        """)
        let promptEvent = try XCTUnwrap(AgentHookEventMapper.map(beforeAgent, provider: .geminiCLI))
        XCTAssertEqual(promptEvent.type, .activity)
        XCTAssertEqual(promptEvent.task, "Add a Gemini integration")
        XCTAssertEqual(promptEvent.state, .thinking)

        let beforeTool = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "BeforeTool",
          "tool_name": "run_shell_command",
          "tool_input": {"command": "swift test"}
        }
        """)
        let toolEvent = try XCTUnwrap(AgentHookEventMapper.map(beforeTool, provider: .geminiCLI))
        XCTAssertEqual(toolEvent.type, .toolStarted)
        XCTAssertEqual(toolEvent.provider, .geminiCLI)

        let notification = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "Notification",
          "notification_type": "ToolPermission",
          "message": "Approve run_shell_command"
        }
        """)
        let waiting = try XCTUnwrap(AgentHookEventMapper.map(notification, provider: .geminiCLI))
        XCTAssertEqual(waiting.type, .waiting)
        XCTAssertEqual(waiting.activity, "Approve run_shell_command")

        let afterAgent = try decode("""
        {
          "session_id": "gemini-1",
          "cwd": "/tmp/AgentsNotch",
          "hook_event_name": "AfterAgent",
          "prompt_response": "Gemini integration complete"
        }
        """)
        let completed = try XCTUnwrap(AgentHookEventMapper.map(afterAgent, provider: .geminiCLI))
        XCTAssertEqual(completed.type, .completed)
        XCTAssertEqual(completed.activity, "Gemini integration complete")
    }

    @MainActor
    func testGeminiIntegrationWritesOfficialHookNamesAndMillisecondTimeouts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotchGeminiTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let relay = root.appendingPathComponent("bundle/agentsnotch-hook")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relay.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("relay".utf8).write(to: relay)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: relay.path)

        let manager = ProviderIntegrationManager(
            provider: .geminiCLI,
            homeDirectoryURL: home,
            bundledRelayURL: relay
        )
        manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        let settingsURL = home.appendingPathComponent(".gemini/settings.json")
        let rootObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let hooks = try XCTUnwrap(rootObject["hooks"] as? [String: Any])
        let expected = ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        XCTAssertEqual(Set(hooks.keys), Set(expected))
        for eventName in expected {
            let groups = try XCTUnwrap(hooks[eventName] as? [[String: Any]])
            let handlers = try XCTUnwrap(groups.first?["hooks"] as? [[String: Any]])
            XCTAssertEqual(handlers.first?["timeout"] as? Int, 5_000)
            XCTAssertTrue((handlers.first?["command"] as? String)?.contains("--provider 'gemini-cli'") == true)
        }
    }

    private func decode(_ json: String) throws -> AgentHookPayload {
        try AgentHookInput.decode(Data(json.utf8))
    }
}
