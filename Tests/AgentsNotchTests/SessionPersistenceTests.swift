@testable import AgentsNotch
import AgentsNotchCore
import Foundation
import XCTest

final class SessionPersistenceTests: XCTestCase {
    func testMalformedHistoryIsQuarantinedAndRewritten() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        try Data("{broken".utf8).write(to: fixture.fileURL)
        let persistence = SessionPersistence(fileURL: fixture.fileURL)

        let result = await persistence.load()

        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertTrue(result.canSafelyWrite)
        XCTAssertNotNil(result.recoveryMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fileURL.path + ".corrupt"))

        let saveError = await persistence.save([])
        XCTAssertNil(saveError)
        let repaired = try Data(contentsOf: fixture.fileURL)
        XCTAssertEqual(try JSONDecoder.agentsNotch.decode([AgentSession].self, from: repaired), [])
    }

    @MainActor
    func testRuntimeDoesNotOverwriteUnreadableHistoryWhenQuarantineFails() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let unreadableHistory = Data("{broken".utf8)
        try unreadableHistory.write(to: fixture.fileURL)
        let persistence = SessionPersistence(
            fileURL: fixture.fileURL,
            quarantineUnreadableFile: { _, _ in throw PersistenceTestError.quarantineFailed }
        )
        let runtime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false,
            persistDebounceDuration: .milliseconds(40),
            persistMaximumDelay: .milliseconds(100)
        )

        await runtime.start()
        XCTAssertNotNil(runtime.persistenceError)
        XCTAssertNil(runtime.persistenceRecoveryNotice)
        var saveInvocationCount = await persistence.saveInvocationCount
        XCTAssertEqual(saveInvocationCount, 0)

        runtime.activity.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:in-memory-only",
            provider: .codex,
            state: .running
        ))
        try await Task.sleep(for: .milliseconds(150))
        saveInvocationCount = await persistence.saveInvocationCount
        XCTAssertEqual(saveInvocationCount, 0)

        runtime.stop()
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), unreadableHistory)
    }

    @MainActor
    func testRuntimeDoesNotPromoteProviderTelemetryForRejectedProtocol() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let runtime = AppRuntime(
            persistence: SessionPersistence(fileURL: fixture.fileURL),
            socketURL: fixture.socketURL,
            monitorProviders: false
        )
        await runtime.start()
        defer { runtime.stop() }

        try UnixSocketClient.send(AgentEvent(
            protocolVersion: 2,
            type: .activity,
            sessionId: "codex:future-protocol",
            provider: .codex,
            state: .running
        ), to: fixture.socketURL)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertTrue(runtime.activity.sessions.isEmpty)
        XCTAssertNil(runtime.lastEventReceivedAt[.codex])

        try UnixSocketClient.send(AgentEvent(
            type: .activity,
            sessionId: "codex:supported-protocol",
            provider: .codex,
            state: .running
        ), to: fixture.socketURL)
        for _ in 0..<30 where runtime.lastEventReceivedAt[.codex] == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(runtime.activity.sessions.count, 1)
        XCTAssertNotNil(runtime.lastEventReceivedAt[.codex])
    }

    @MainActor
    func testRuntimeBuffersStartupEventsAndFlushesLatestStateOnStop() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let persistence = SessionPersistence(fileURL: fixture.fileURL, loadDelay: .milliseconds(180))
        let runtime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false
        )
        let startTask = Task { await runtime.start() }

        for _ in 0..<30 where !FileManager.default.fileExists(atPath: fixture.socketURL.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        try UnixSocketClient.send(AgentEvent(
            type: .activity,
            sessionId: "codex:startup-event",
            provider: .codex,
            task: "Arrived during restore",
            state: .running
        ), to: fixture.socketURL)

        await startTask.value
        XCTAssertEqual(runtime.activity.sessions.map(\.id), ["codex:startup-event"])
        runtime.activity.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:startup-event",
            provider: .codex,
            state: .completed
        ))
        runtime.stop()

        let saved = await persistence.load().sessions
        XCTAssertEqual(saved.first?.id, "codex:startup-event")
        XCTAssertEqual(saved.first?.state, .completed)
    }

    @MainActor
    func testStopSupersedesAnOlderSaveAlreadyInFlight() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let blocker = OrderedSaveBlocker()
        defer { blocker.resume() }
        let persistence = SessionPersistence(
            fileURL: fixture.fileURL,
            beforeOrderedSave: { blocker.block() }
        )
        let runtime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false,
            persistDebounceDuration: .milliseconds(10),
            persistMaximumDelay: .seconds(1)
        )
        await runtime.start()

        runtime.activity.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:in-flight",
            provider: .codex,
            state: .running
        ))
        await blocker.waitUntilBlocked()

        runtime.activity.ingest(AgentEvent(
            type: .completed,
            sessionId: "codex:in-flight",
            provider: .codex,
            state: .completed
        ))
        runtime.stop()
        blocker.resume()

        let saved = await persistence.load().sessions
        XCTAssertEqual(saved.first?.id, "codex:in-flight")
        XCTAssertEqual(saved.first?.state, .completed)
    }

    @MainActor
    func testRuntimeDebouncesBurstPersistenceWrites() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let persistence = SessionPersistence(fileURL: fixture.fileURL)
        let runtime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false,
            persistDebounceDuration: .milliseconds(120),
            persistMaximumDelay: .seconds(1)
        )
        await runtime.start()
        defer { runtime.stop() }
        let startupSaveCount = await persistence.saveInvocationCount

        for index in 0..<20 {
            runtime.activity.ingest(AgentEvent(
                type: .activity,
                sessionId: "burst",
                provider: .codex,
                activity: "Event \(index)",
                state: .running,
                timestamp: Date().addingTimeInterval(TimeInterval(index))
            ))
        }

        try await Task.sleep(for: .milliseconds(50))
        let saveCountDuringBurst = await persistence.saveInvocationCount
        XCTAssertEqual(saveCountDuringBurst, startupSaveCount)
        try await Task.sleep(for: .milliseconds(160))
        let saveCountAfterDebounce = await persistence.saveInvocationCount
        XCTAssertEqual(saveCountAfterDebounce, startupSaveCount + 1)
    }

    @MainActor
    func testRuntimeMarksRestoredRunnersUnknownInsteadOfCompleted() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let persistence = SessionPersistence(fileURL: fixture.fileURL)
        let running = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:mid-task",
            provider: .codex,
            task: "Twenty-minute refactor",
            activity: "Running tests",
            state: .running,
            timestamp: Date(timeIntervalSince1970: 200)
        ))
        let waiting = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "claude-code:approval",
            provider: .claudeCode,
            activity: "Needs approval",
            state: .waitingForUser,
            timestamp: Date(timeIntervalSince1970: 210)
        ))
        let saveError = await persistence.save([running, waiting])
        XCTAssertNil(saveError)

        let runtime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false
        )
        await runtime.start()
        defer { runtime.stop() }

        let midTask = try XCTUnwrap(runtime.activity.sessions.first { $0.id == "codex:mid-task" })
        XCTAssertEqual(midTask.state, .unknown)
        XCTAssertEqual(midTask.currentActivity, "Running tests")
        XCTAssertNil(midTask.completedAt)
        XCTAssertEqual(
            runtime.activity.sessions.first { $0.id == "claude-code:approval" }?.state,
            .waitingForUser
        )
    }

    @MainActor
    func testRuntimeGrokRestoreRepairsLegacyRecencyAndStaysIdempotent() async throws {
        let fixture = try PersistenceFixture()
        defer { fixture.remove() }
        let persistence = SessionPersistence(fileURL: fixture.fileURL)
        let grokHome = fixture.root.appendingPathComponent("grok", isDirectory: true)
        let workspace = "/tmp/AgentsNotch"
        let workflowUpdatedAt = Date(timeIntervalSince1970: 110)
        let workflowDirectory = grokHome
            .appendingPathComponent("sessions/%2Ftmp%2FAgentsNotch/parent/workflows/run", isDirectory: true)
        try FileManager.default.createDirectory(at: workflowDirectory, withIntermediateDirectories: true)
        let workflowStateURL = workflowDirectory.appendingPathComponent("state.json")
        try Data("""
        {
          "version": 4,
          "state": {
            "run_id": "workflow-1",
            "name": "audit-and-fix",
            "objective": "Audit and fix Agents Notch",
            "status": "completed",
            "phases": [{"title": "Audit"}, {"title": "Confirm"}],
            "current_phase": "Confirm"
          }
        }
        """.utf8).write(to: workflowStateURL)
        try FileManager.default.setAttributes(
            [.modificationDate: workflowUpdatedAt],
            ofItemAtPath: workflowStateURL.path
        )

        var grok = AgentSession(event: AgentEvent(
            type: .started,
            sessionId: "grok:parent",
            provider: .grok,
            task: "Audit and fix Agents Notch",
            state: .starting,
            timestamp: Date(timeIntervalSince1970: 100),
            workingDirectory: workspace
        ))
        let workflowUpdate = AgentWorkflowUpdate(
            id: "workflow-1",
            title: "audit-and-fix",
            status: .completed,
            steps: [
                AgentStep(id: "workflow-1:phase:0", title: "Audit", status: .completed),
                AgentStep(id: "workflow-1:phase:1", title: "Confirm", status: .completed),
            ]
        )
        // Simulate enough Date()-stamped startup reconciliations to evict the
        // original lifecycle events from the ten-event diagnostic history.
        for offset in 0..<12 {
            grok.apply(AgentEvent(
                type: .activity,
                sessionId: "grok:parent",
                provider: .grok,
                activity: "Workflow · Confirm",
                state: .completed,
                timestamp: Date(timeIntervalSince1970: 500 + TimeInterval(offset)),
                metadata: ["hookEvent": "grokWorkflowState"],
                workflowUpdate: workflowUpdate
            ))
        }
        let codex = AgentSession(event: AgentEvent(
            type: .completed,
            sessionId: "codex:newer",
            provider: .codex,
            task: "Newer Codex thread",
            state: .completed,
            timestamp: Date(timeIntervalSince1970: 400)
        ))
        let saveError = await persistence.save([grok, codex])
        XCTAssertNil(saveError)

        let firstRuntime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false,
            grokHome: grokHome
        )
        await firstRuntime.start()
        XCTAssertEqual(firstRuntime.activity.listSessions.map(\.id), ["codex:newer", "grok:parent"])
        let repaired = try XCTUnwrap(firstRuntime.activity.sessions.first { $0.id == "grok:parent" })
        XCTAssertEqual(repaired.updatedAt, workflowUpdatedAt)
        XCTAssertEqual(repaired.completedAt, workflowUpdatedAt)
        XCTAssertEqual(repaired.workflows.first?.updatedAt, workflowUpdatedAt)
        XCTAssertFalse(repaired.recentEvents.contains { $0.timestamp > workflowUpdatedAt })
        firstRuntime.stop()

        let secondRuntime = AppRuntime(
            persistence: persistence,
            socketURL: fixture.socketURL,
            monitorProviders: false,
            grokHome: grokHome
        )
        await secondRuntime.start()
        let restoredAgain = try XCTUnwrap(secondRuntime.activity.sessions.first { $0.id == "grok:parent" })
        XCTAssertEqual(restoredAgain, repaired)
        XCTAssertEqual(secondRuntime.activity.listSessions.map(\.id), ["codex:newer", "grok:parent"])
        secondRuntime.stop()
    }

    func testOriginMetadataRoundTripsThroughSessionPersistenceModel() throws {
        let origin = AgentOrigin(
            bundleIdentifier: "com.apple.Terminal",
            processIdentifier: 42,
            processStartedAt: Date(timeIntervalSince1970: 100),
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
}

private enum PersistenceTestError: LocalizedError {
    case quarantineFailed

    var errorDescription: String? { "Simulated quarantine failure." }
}

private final class OrderedSaveBlocker: @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let continuation = DispatchSemaphore(value: 0)

    func block() {
        started.signal()
        continuation.wait()
    }

    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [started] in
                started.wait()
                continuation.resume()
            }
        }
    }

    func resume() {
        continuation.signal()
    }
}

private final class PersistenceFixture: @unchecked Sendable {
    let root: URL
    let fileURL: URL
    let socketURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotchPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = root.appendingPathComponent("sessions.json")
        socketURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("an-\(UUID().uuidString.prefix(8)).sock")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: socketURL)
        try? FileManager.default.removeItem(atPath: socketURL.path + ".lock")
    }
}
