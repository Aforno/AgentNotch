@testable import AgentsNotch
import AgentsNotchCore
import Foundation
import XCTest

final class ProviderIntegrationManagerTests: XCTestCase {
    @MainActor
    func testInstallIsIdempotentAndUninstallPreservesExistingConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeJSON([
            "theme": "dark",
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [[
                        "type": "command",
                        "command": "echo existing",
                    ]],
                ]],
            ],
        ], to: hooksURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksURL.path)

        let manager = fixture.manager(provider: .codex)
        manager.install()
        manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(try Data(contentsOf: manager.installedRelayURL), Data("relay-v1".utf8))
        let permissions = try FileManager.default.attributesOfItem(
            atPath: manager.installedRelayURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o755)

        let installedRoot = try Self.readJSON(at: hooksURL)
        XCTAssertEqual(installedRoot["theme"] as? String, "dark")
        let installedHooks = try XCTUnwrap(installedRoot["hooks"] as? [String: Any])
        let preToolUse = try XCTUnwrap(installedHooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(preToolUse.count, 2, "reinstalling must not duplicate the relay")
        XCTAssertEqual(Self.commands(in: preToolUse).filter { $0.contains("agentsnotch-hook") }.count, 1)

        manager.uninstall()

        XCTAssertEqual(manager.status, .notInstalled)
        let uninstalledRoot = try Self.readJSON(at: hooksURL)
        XCTAssertEqual(uninstalledRoot["theme"] as? String, "dark")
        let uninstalledHooks = try XCTUnwrap(uninstalledRoot["hooks"] as? [String: Any])
        let remainingPreToolUse = try XCTUnwrap(uninstalledHooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(Self.commands(in: remainingPreToolUse), ["echo existing"])
        XCTAssertEqual(uninstalledHooks.keys.sorted(), ["PreToolUse"])
        let hooksPermissions = try FileManager.default.attributesOfItem(
            atPath: hooksURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(hooksPermissions?.intValue, 0o600)
    }

    @MainActor
    func testInstallPreservesSymlinkedConfigurationFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sharedURL = fixture.root.appendingPathComponent("dotfiles/hooks.json")
        try FileManager.default.createDirectory(
            at: sharedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeJSON(["hooks": [:]], to: sharedURL)
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: hooksURL, withDestinationURL: sharedURL)

        let manager = fixture.manager(provider: .codex)
        manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: hooksURL.path),
            sharedURL.path
        )
        let root = try Self.readJSON(at: sharedURL)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertFalse(hooks.isEmpty)
    }

    @MainActor
    func testUninstallRemovesProviderOwnedLegacyEventHooks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .codex)
        manager.install()
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        var root = try Self.readJSON(at: hooksURL)
        var hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        hooks["LegacyLifecycleEvent"] = [[
            "hooks": [
                ["type": "command", "command": "echo preserve"],
                [
                    "type": "command",
                    "command": "'\(manager.installedRelayURL.path)' --provider 'codex'",
                ],
            ],
        ]]
        root["hooks"] = hooks
        try Self.writeJSON(root, to: hooksURL)

        manager.uninstall()

        let removedRoot = try Self.readJSON(at: hooksURL)
        let removedHooks = try XCTUnwrap(removedRoot["hooks"] as? [String: Any])
        let legacy = try XCTUnwrap(removedHooks["LegacyLifecycleEvent"] as? [[String: Any]])
        XCTAssertEqual(Self.commands(in: legacy), ["echo preserve"])
    }

    @MainActor
    func testInstallRefusesToOverwriteInvalidRootConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooksURL = fixture.home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("[1, 2, 3]\n".utf8)
        try original.write(to: hooksURL)

        let manager = fixture.manager(provider: .claudeCode)
        manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    @MainActor
    func testInstallRefusesToReplaceInvalidHooksSection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("{\"hooks\":[\"preserve me\"],\"theme\":\"dark\"}".utf8)
        try original.write(to: hooksURL)

        let manager = fixture.manager(provider: .codex)
        manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    @MainActor
    func testInstallFailsInsteadOfReportingPartialMalformedEventConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeJSON([
            "hooks": ["PreToolUse": ["not": "an array"]],
        ], to: hooksURL)
        let original = try Data(contentsOf: hooksURL)

        let manager = fixture.manager(provider: .codex)
        manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    @MainActor
    func testSharedSymlinkedConfigurationKeepsProviderSpecificCommandsSeparate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sharedURL = fixture.root.appendingPathComponent("dotfiles/shared-hooks.json")
        try FileManager.default.createDirectory(
            at: sharedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeJSON(["hooks": [:]], to: sharedURL)
        for path in [".codex/hooks.json", ".claude/settings.json"] {
            let linkURL = fixture.home.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: linkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: sharedURL)
        }

        let codex = fixture.manager(provider: .codex)
        let claude = fixture.manager(provider: .claudeCode)
        codex.install()
        claude.install()
        claude.uninstall()

        let root = try Self.readJSON(at: sharedURL)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let commands = Self.commands(in: preTool)
        XCTAssertEqual(commands.filter { $0.contains("--provider 'codex'") }.count, 1)
        XCTAssertFalse(commands.contains { $0.contains("--provider 'claude-code'") })
    }

    @MainActor
    func testMonitoringRefreshesAnInstalledRelayWithoutChangingHooks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .grok)
        manager.install()
        let hooksURL = fixture.home
            .appendingPathComponent(".grok/hooks", isDirectory: true)
            .appendingPathComponent("agentsnotch.json")
        let hooksBeforeRefresh = try Data(contentsOf: hooksURL)

        try Data("relay-v2".utf8).write(to: fixture.bundledRelay, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.bundledRelay.path
        )
        manager.prepareForMonitoring()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(try Data(contentsOf: manager.installedRelayURL), Data("relay-v2".utf8))
        XCTAssertEqual(try Data(contentsOf: hooksURL), hooksBeforeRefresh)
    }

    @MainActor
    func testCodexPromotesToConnectedAfterGenuineEventAndRefreshDoesNotDemote() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .codex)

        manager.install()
        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNotNil(manager.trustInstructions)
        XCTAssertFalse(manager.hasReceivedEvent)

        manager.noteEventReceived()
        XCTAssertEqual(manager.status, .connected)
        XCTAssertTrue(manager.hasReceivedEvent)
        XCTAssertNil(manager.trustInstructions)

        manager.refreshStatus()
        XCTAssertEqual(manager.status, .connected, "refresh must not demote a verified integration")

        manager.refreshStatus(hasReceivedEvent: true)
        XCTAssertEqual(manager.status, .connected)

        manager.uninstall()
        XCTAssertEqual(manager.status, .notInstalled)
        XCTAssertFalse(manager.hasReceivedEvent)
    }

    @MainActor
    func testRefreshStatusAcceptsRuntimeEventEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .claudeCode)
        manager.install()
        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.trustInstructions, "trust warning is Codex-only")

        manager.refreshStatus(hasReceivedEvent: true)
        XCTAssertEqual(manager.status, .connected)
        XCTAssertTrue(manager.hasReceivedEvent)
    }

    @MainActor
    func testMissingBundledRelayDoesNotModifyProviderConfiguration() throws {
        let fixture = try Fixture(createBundledRelay: false)
        defer { fixture.remove() }
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        let manager = fixture.manager(provider: .codex)

        manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(manager.lastError, "The bundled agent relay could not be found. Launch the packaged Agents Notch app.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: hooksURL.path))
    }

    private static func readJSON(at url: URL) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(object as? [String: Any])
    }

    private static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func commands(in groups: [[String: Any]]) -> [String] {
        groups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let home: URL
    let bundledRelay: URL

    init(createBundledRelay: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentsNotchIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        bundledRelay = root.appendingPathComponent("bundle/agentsnotch-hook")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if createBundledRelay {
            try FileManager.default.createDirectory(
                at: bundledRelay.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("relay-v1".utf8).write(to: bundledRelay)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: bundledRelay.path
            )
        }
    }

    @MainActor
    func manager(provider: AgentProvider) -> ProviderIntegrationManager {
        ProviderIntegrationManager(
            provider: provider,
            homeDirectoryURL: home,
            bundledRelayURL: bundledRelay
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
