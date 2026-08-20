#if DEBUG
@testable import AgentsNotch
import AgentsNotchCore
import XCTest

final class CodexSessionTitleResolverTests: XCTestCase {
    func testLastMatchingThreadNameWins() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":"First draft title","updated_at":"2026-08-13T00:00:00Z"}
        {"id":"thr_other","thread_name":"Unrelated","updated_at":"2026-08-13T00:01:00Z"}
        {"id":"thr_123","thread_name":"Review recent changes","updated_at":"2026-08-13T00:02:00Z"}
        """)

        XCTAssertEqual(
            CodexSessionTitleResolver.title(forNativeSessionId: "thr_123", codexHome: home),
            "Review recent changes"
        )
    }

    func testCamelCaseThreadNameIsAccepted() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","threadName":"Review recent changes"}
        """)

        XCTAssertEqual(
            CodexSessionTitleResolver.title(forNativeSessionId: "thr_123", codexHome: home),
            "Review recent changes"
        )
    }

    func testSnakeCaseThreadNameWinsWhenBothAliasesExist() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":"Review recent changes","threadName":"Camel leftover"}
        """)

        XCTAssertEqual(
            CodexSessionTitleResolver.title(forNativeSessionId: "thr_123", codexHome: home),
            "Review recent changes"
        )
    }

    func testMalformedThreadNameFallsThroughToAlternateAlias() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":123,"threadName":"Review recent changes"}
        """)

        XCTAssertEqual(
            CodexSessionTitleResolver.title(forNativeSessionId: "thr_123", codexHome: home),
            "Review recent changes"
        )
    }

    func testUnknownSessionReturnsNil() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":"Review recent changes"}
        """)

        XCTAssertNil(CodexSessionTitleResolver.title(forNativeSessionId: "missing", codexHome: home))
    }

    func testTitleLookupDoesNotReadPastTheTailLimit() throws {
        let oldRecord = Data("{\"id\":\"thr_old\",\"thread_name\":\"Stale title\"}\n".utf8)
        let fillerLine = "{\"id\":\"other\",\"padding\":\"\(String(repeating: "x", count: 1_024))\"}\n"
        let fillerCount = CodexSessionTitleResolver.maximumIndexTailBytes / fillerLine.utf8.count + 2
        var index = oldRecord
        index.append(Data(String(repeating: fillerLine, count: fillerCount).utf8))
        let home = try temporaryCodexHome(index: index)

        XCTAssertNil(CodexSessionTitleResolver.title(forNativeSessionId: "thr_old", codexHome: home))
    }

    func testThreadIDUsesRootSessionIdentity() {
        XCTAssertEqual(
            CodexSessionTitleResolver.threadID(fromCanonicalSessionID: "codex:thr_123"),
            "thr_123"
        )
        XCTAssertEqual(
            CodexSessionTitleResolver.threadID(fromCanonicalSessionID: "codex:thr_123:agent-1"),
            "thr_123"
        )
        XCTAssertNil(CodexSessionTitleResolver.threadID(fromCanonicalSessionID: "grok:thr_123"))
    }

    @MainActor
    func testOfficialTitleReplacesLastUserMessage() {
        let service = AgentActivityService()
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:thr_123",
            provider: .codex,
            task: "do that change",
            activity: "Thinking",
            state: .thinking
        ))
        service.ingest(AgentEvent(
            type: .activity,
            sessionId: "codex:thr_123",
            provider: .codex,
            task: "Review recent changes",
            activity: "Thinking",
            state: .thinking,
            metadata: ["titleSource": "session"]
        ))

        XCTAssertEqual(service.sessions[0].task, "Review recent changes")
    }

    func testRestorerEmitsOfficialTitleForPromptDerivedTask() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":"Review recent changes"}
        """)
        let session = AgentSession(event: AgentEvent(
            type: .completed,
            sessionId: "codex:thr_123",
            provider: .codex,
            task: "do that change",
            activity: "Implemented the canonical identity fix.",
            state: .completed
        ))

        let events = CodexSessionRestorer.titleEvents(in: [session], codexHome: home)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].task, "Review recent changes")
        XCTAssertEqual(events[0].metadata?["titleSource"], "session")
    }

    func testRestorerEmitsIndexEvidenceWhenTitleAlreadyMatches() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":"Review recent changes"}
        """)
        let session = AgentSession(event: AgentEvent(
            type: .completed,
            sessionId: "codex:thr_123",
            provider: .codex,
            task: "Review recent changes",
            activity: "Implemented the canonical identity fix.",
            state: .completed
        ))

        let events = CodexSessionRestorer.titleEvents(in: [session], codexHome: home)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].metadata?["titleSource"], "session")
    }

    func testRestorerDoesNotRestampWhenOfficialTitleEvidenceExists() throws {
        let home = try temporaryCodexHome(index: """
        {"id":"thr_123","thread_name":"Review recent changes"}
        """)
        let session = AgentSession(event: AgentEvent(
            type: .completed,
            sessionId: "codex:thr_123",
            provider: .codex,
            task: "Review recent changes",
            activity: "Implemented the canonical identity fix.",
            state: .completed,
            metadata: ["titleSource": "session"]
        ))

        XCTAssertTrue(session.hasOfficialSessionTitle)
        XCTAssertTrue(CodexSessionRestorer.titleEvents(in: [session], codexHome: home).isEmpty)
    }

    private func temporaryCodexHome(index: String) throws -> URL {
        try temporaryCodexHome(index: Data(index.utf8))
    }

    private func temporaryCodexHome(index: Data) throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotch-CodexTitle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try index.write(to: home.appendingPathComponent("session_index.jsonl"))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: home)
        }
        return home
    }
}
#endif
