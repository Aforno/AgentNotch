import AgentsNotchCore
import XCTest

final class ProjectIdentityTests: XCTestCase {
    func testMissingGitUsesFolderName() {
        XCTAssertEqual(
            ProjectIdentity.name(fromWorkingDirectory: "/Users/me/AgentNotch"),
            "AgentNotch"
        )
    }

    func testEmptyDirectoryIsAbsent() {
        XCTAssertNil(ProjectIdentity.name(fromWorkingDirectory: "  "))
    }

    func testRegularCheckoutUsesItsOwnFolderName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("regular-repo-\(UUID().uuidString)", isDirectory: true)
        let repo = root.appendingPathComponent("AgentNotch", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(ProjectIdentity.name(fromWorkingDirectory: repo.path), "AgentNotch")
    }

    func testLinkedWorktreeUsesMainRepositoryName() throws {
        let fixture = try LinkedGitWorktree.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertEqual(fixture.worktreeName, "t3code-223a0195")
        XCTAssertEqual(
            ProjectIdentity.name(fromWorkingDirectory: fixture.worktree.path),
            "AgentNotch"
        )
    }

    func testRelativeGitDirResolvesToMainRepository() throws {
        let fixture = try LinkedGitWorktree.make(relativeGitDir: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertEqual(
            ProjectIdentity.name(fromWorkingDirectory: fixture.worktree.path),
            "AgentNotch"
        )
    }

    func testBareRepositoryWorktreeDropsGitSuffix() throws {
        let fixture = try LinkedGitWorktree.make(bare: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertEqual(
            ProjectIdentity.name(fromWorkingDirectory: fixture.worktree.path),
            "AgentNotch"
        )
    }

    func testClaudeStyleNestedWorktreeDoesNotUseParentFolder() throws {
        let fixture = try LinkedGitWorktree.make(
            worktreeName: "charming-dewdney-d52f1b",
            worktreeSubpath: "AgentNotch/.claude/worktrees/charming-dewdney-d52f1b"
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        XCTAssertEqual(
            ProjectIdentity.name(fromWorkingDirectory: fixture.worktree.path),
            "AgentNotch"
        )
    }

    func testSeparateGitDirWithoutCommondirKeepsCheckoutFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("separate-git-dir-\(UUID().uuidString)", isDirectory: true)
        let checkout = root.appendingPathComponent("AgentNotch", isDirectory: true)
        let gitDir = root.appendingPathComponent("git-storage", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "gitdir: \(gitDir.path)\n".write(
            to: checkout.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(ProjectIdentity.name(fromWorkingDirectory: checkout.path), "AgentNotch")
    }

    func testSessionStartPlaceholderYieldsToPromptOnAWorktree() throws {
        let fixture = try LinkedGitWorktree.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var session = AgentSession(event: AgentEvent(
            type: .started,
            sessionId: "codex:worktree",
            provider: .codex,
            task: ProjectIdentity.name(fromWorkingDirectory: fixture.worktree.path),
            activity: "Session started",
            state: .starting,
            workingDirectory: fixture.worktree.path
        ))
        XCTAssertEqual(session.task, "AgentNotch")
        XCTAssertEqual(session.projectName, "AgentNotch")

        session.apply(AgentEvent(
            type: .activity,
            sessionId: "codex:worktree",
            provider: .codex,
            task: "Fix worktree project names",
            activity: "Thinking",
            state: .thinking,
            workingDirectory: fixture.worktree.path
        ))

        XCTAssertEqual(session.task, "Fix worktree project names")
        XCTAssertEqual(session.projectName, "AgentNotch")
    }

    func testSessionPersistsRepositoryNameAfterWorktreeRemoval() throws {
        let fixture = try LinkedGitWorktree.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let session = AgentSession(event: AgentEvent(
            type: .completed,
            sessionId: "codex:removed-worktree",
            provider: .codex,
            task: "Fix worktree project names",
            state: .completed,
            workingDirectory: fixture.worktree.path
        ))
        let data = try JSONEncoder().encode(session)

        try FileManager.default.removeItem(at: fixture.root)

        var restored = try JSONDecoder().decode(AgentSession.self, from: data)
        XCTAssertEqual(restored.projectName, "AgentNotch")

        restored.apply(AgentEvent(
            type: .completed,
            sessionId: restored.id,
            provider: .codex,
            state: .completed,
            timestamp: restored.updatedAt.addingTimeInterval(1),
            workingDirectory: fixture.worktree.path
        ))
        XCTAssertEqual(restored.projectName, "AgentNotch")
    }

    func testLegacySessionDerivesMissingProjectName() throws {
        let session = AgentSession(event: AgentEvent(
            type: .completed,
            sessionId: "codex:legacy",
            provider: .codex,
            task: "Legacy session",
            state: .completed,
            workingDirectory: "/Users/me/AgentNotch"
        ))
        let data = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "projectName")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(AgentSession.self, from: legacyData)

        XCTAssertEqual(restored.projectName, "AgentNotch")
    }
}
