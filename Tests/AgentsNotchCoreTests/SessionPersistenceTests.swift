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
        XCTAssertTrue(result.needsRewrite)
        XCTAssertNotNil(result.recoveryMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fileURL.path + ".corrupt"))

        let saveError = await persistence.save([])
        XCTAssertNil(saveError)
        let repaired = try Data(contentsOf: fixture.fileURL)
        XCTAssertEqual(try JSONDecoder.agentsNotch.decode([AgentSession].self, from: repaired), [])
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
            sessionId: "startup-event",
            provider: .codex,
            task: "Arrived during restore",
            state: .running
        ), to: fixture.socketURL)

        await startTask.value
        XCTAssertEqual(runtime.activity.sessions.map(\.id), ["startup-event"])
        runtime.activity.ingest(AgentEvent(
            type: .completed,
            sessionId: "startup-event",
            provider: .codex,
            state: .completed
        ))
        runtime.stop()

        let saved = await persistence.load().sessions
        XCTAssertEqual(saved.first?.id, "startup-event")
        XCTAssertEqual(saved.first?.state, .completed)
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
