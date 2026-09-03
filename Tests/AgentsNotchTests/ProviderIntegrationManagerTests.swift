@testable import AgentsNotch
import AgentsNotchCore
import Foundation
import XCTest

final class ProviderIntegrationManagerTests: XCTestCase {
    func testStatusReadinessFlagsMatchLifecycle() {
        XCTAssertFalse(ProviderIntegrationStatus.notInstalled.isInstalled)
        XCTAssertFalse(ProviderIntegrationStatus.notInstalled.isConnected)
        XCTAssertTrue(ProviderIntegrationStatus.awaitingFirstEvent.isInstalled)
        XCTAssertFalse(ProviderIntegrationStatus.awaitingFirstEvent.isConnected)
        XCTAssertTrue(ProviderIntegrationStatus.connected.isInstalled)
        XCTAssertTrue(ProviderIntegrationStatus.connected.isConnected)
        XCTAssertFalse(ProviderIntegrationStatus.unavailable("Unavailable").isInstalled)
    }

    @MainActor
    func testInstallIsIdempotentAndUninstallPreservesExistingConfiguration() async throws {
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
        await manager.install()
        await manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        XCTAssertNotNil(manager.trustInstructions)
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
        XCTAssertEqual(Self.commands(in: preToolUse).filter { $0.contains("agentnotch-hook") }.count, 1)

        await manager.uninstall()

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
    func testInstallPreservesSymlinkedConfigurationFile() async throws {
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
        await manager.install()

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
    func testUninstallRemovesProviderOwnedLegacyEventHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .codex)
        await manager.install()
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

        await manager.uninstall()

        let removedRoot = try Self.readJSON(at: hooksURL)
        let removedHooks = try XCTUnwrap(removedRoot["hooks"] as? [String: Any])
        let legacy = try XCTUnwrap(removedHooks["LegacyLifecycleEvent"] as? [[String: Any]])
        XCTAssertEqual(Self.commands(in: legacy), ["echo preserve"])
    }

    @MainActor
    func testInstallRefusesToOverwriteInvalidRootConfiguration() async throws {
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
        await manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    @MainActor
    func testInstallRefusesToReplaceInvalidHooksSection() async throws {
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
        await manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    @MainActor
    func testInstallFailsInsteadOfReportingPartialMalformedEventConfiguration() async throws {
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
        await manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(try Data(contentsOf: hooksURL), original)
    }

    @MainActor
    func testSharedSymlinkedConfigurationKeepsProviderSpecificCommandsSeparate() async throws {
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
        await codex.install()
        await claude.install()
        await claude.uninstall()

        let root = try Self.readJSON(at: sharedURL)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let preTool = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let commands = Self.commands(in: preTool)
        XCTAssertEqual(commands.filter { $0.contains("--provider 'codex'") }.count, 1)
        XCTAssertFalse(commands.contains { $0.contains("--provider 'claude-code'") })
    }

    @MainActor
    func testMonitoringRefreshesAnInstalledRelayWithoutChangingHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .grok)
        await manager.install()
        let hooksURL = fixture.home
            .appendingPathComponent(".grok/hooks", isDirectory: true)
            .appendingPathComponent("agentnotch.json")
        let hooksBeforeRefresh = try Data(contentsOf: hooksURL)

        try Data("relay-v2".utf8).write(to: fixture.bundledRelay, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.bundledRelay.path
        )
        await manager.prepareForMonitoring()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        XCTAssertEqual(try Data(contentsOf: manager.installedRelayURL), Data("relay-v2".utf8))
        XCTAssertEqual(try Data(contentsOf: hooksURL), hooksBeforeRefresh)
    }

    @MainActor
    func testCodexPromotesToConnectedAfterGenuineEventAndRefreshDoesNotDemote() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .codex)

        await manager.install()
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

        await manager.uninstall()
        XCTAssertEqual(manager.status, .notInstalled)
        XCTAssertFalse(manager.hasReceivedEvent)
    }

    @MainActor
    func testRefreshStatusAcceptsRuntimeEventEvidence() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .claudeCode)
        await manager.install()
        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.trustInstructions, "trust warning is Codex-only")

        manager.refreshStatus(hasReceivedEvent: true)
        XCTAssertEqual(manager.status, .connected)
        XCTAssertTrue(manager.hasReceivedEvent)
    }

    @MainActor
    func testClaudeInstallWritesDocumentedAsynchronousObserverHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .claudeCode)
        await manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        let settingsURL = fixture.home.appendingPathComponent(".claude/settings.json")
        let root = try Self.readJSON(at: settingsURL)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let expected = [
            "SessionStart",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "PostToolUseFailure",
            "PermissionRequest",
            "PermissionDenied",
            "Notification",
            "Elicitation",
            "ElicitationResult",
            "Stop",
            "StopFailure",
            "SessionEnd",
            "SubagentStart",
            "SubagentStop",
        ]
        XCTAssertEqual(Set(hooks.keys), Set(expected))
        for eventName in expected {
            let groups = try XCTUnwrap(hooks[eventName] as? [[String: Any]])
            let handlers = try XCTUnwrap(groups.first?["hooks"] as? [[String: Any]])
            let handler = try XCTUnwrap(handlers.first)
            XCTAssertEqual(handler["type"] as? String, "command")
            XCTAssertEqual(handler["command"] as? String, manager.installedRelayURL.path)
            XCTAssertEqual(handler["args"] as? [String], ["--provider", "claude-code"])
            XCTAssertEqual(handler["timeout"] as? Int, 5)
            XCTAssertEqual(
                handler["async"] as? Bool,
                true,
                "observer hooks must not block or control Claude Code"
            )
        }
    }

    @MainActor
    func testAnswerFromNotchInstallsBlockingClaudePermissionHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .claudeCode, answersFromNotch: true)
        await manager.install()

        let settingsURL = fixture.home.appendingPathComponent(".claude/settings.json")
        let hooks = try XCTUnwrap(try Self.readJSON(at: settingsURL)["hooks"] as? [String: Any])
        let permission = try XCTUnwrap(
            ((hooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(permission["async"] as? Bool, false)
        XCTAssertEqual(permission["timeout"] as? Int, 120)
        XCTAssertEqual(permission["args"] as? [String], ["--provider", "claude-code", "--answer"])

        let preToolGroups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let passiveGroup = try XCTUnwrap(preToolGroups.first {
            $0["matcher"] as? String == "^(?!AskUserQuestion$|ExitPlanMode$).*"
        })
        let passive = try XCTUnwrap((passiveGroup["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(passive["async"] as? Bool, true)
        XCTAssertEqual(passive["timeout"] as? Int, 5)
        XCTAssertEqual(passive["args"] as? [String], ["--provider", "claude-code"])

        let answerGroup = try XCTUnwrap(preToolGroups.first {
            $0["matcher"] as? String == "AskUserQuestion|ExitPlanMode"
        })
        let interactive = try XCTUnwrap((answerGroup["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(interactive["async"] as? Bool, false)
        XCTAssertEqual(interactive["timeout"] as? Int, 120)
        XCTAssertEqual(interactive["args"] as? [String], ["--provider", "claude-code", "--answer"])

        let sessionStart = try XCTUnwrap(
            ((hooks["SessionStart"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(sessionStart["async"] as? Bool, true)
        XCTAssertEqual(sessionStart["timeout"] as? Int, 5)
        XCTAssertEqual(sessionStart["args"] as? [String], ["--provider", "claude-code", "--answer"])
    }

    @MainActor
    func testPrepareForMonitoringUpgradesLegacyClaudeObserverHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = fixture.manager(provider: .claudeCode)
        await manager.install()
        let settingsURL = fixture.home.appendingPathComponent(".claude/settings.json")
        try Self.writeJSON([
            "hooks": [
                "PermissionRequest": [[
                    "hooks": [[
                        "type": "command",
                        "command": manager.installedRelayURL.path,
                        "args": ["--provider", "claude-code"],
                        "timeout": 5,
                    ]],
                ]],
            ],
        ], to: settingsURL)

        manager.refreshStatus()
        XCTAssertEqual(manager.status, .awaitingFirstEvent)

        await manager.prepareForMonitoring()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        let hooks = try XCTUnwrap(try Self.readJSON(at: settingsURL)["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PermissionDenied"])
        XCTAssertNotNil(hooks["Elicitation"])
        let groups = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        let handler = try XCTUnwrap((groups.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(handler["async"] as? Bool, true)
        XCTAssertEqual(handler["args"] as? [String], ["--provider", "claude-code"])
        XCTAssertEqual(handler["command"] as? String, manager.installedRelayURL.path)
    }

    @MainActor
    func testMissingBundledRelayDoesNotModifyProviderConfiguration() async throws {
        let fixture = try Fixture(createBundledRelay: false)
        defer { fixture.remove() }
        let hooksURL = fixture.home
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("hooks.json")
        let manager = fixture.manager(provider: .codex)

        await manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(manager.lastError, "The bundled agent relay could not be found. Launch the packaged Agent Notch app.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: hooksURL.path))
    }

    @MainActor
    func testCursorInstallUsesNativeHookShapeAndPreservesExistingHooks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hooksURL = fixture.home.appendingPathComponent(".cursor/hooks.json")
        try FileManager.default.createDirectory(
            at: hooksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.writeJSON([
            "version": 1,
            "theme": "preserve",
            "hooks": [
                "preToolUse": [[
                    "command": "echo existing",
                    "timeout": 12,
                ]],
            ],
        ], to: hooksURL)

        let manager = fixture.manager(provider: .cursor)
        await manager.install()
        await manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        let installed = try Self.readJSON(at: hooksURL)
        XCTAssertEqual(installed["theme"] as? String, "preserve")
        XCTAssertEqual(installed["version"] as? Int, 1)
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        let expectedEvents = [
            "sessionStart",
            "beforeSubmitPrompt",
            "preToolUse",
            "postToolUse",
            "postToolUseFailure",
            "stop",
            "sessionEnd",
        ]
        XCTAssertEqual(Set(hooks.keys), Set(expectedEvents))
        for eventName in expectedEvents {
            let handlers = try XCTUnwrap(hooks[eventName] as? [[String: Any]])
            XCTAssertEqual(
                handlers.filter { ($0["command"] as? String)?.contains("--provider 'cursor'") == true }.count,
                1,
                "reinstalling must not duplicate the Cursor observer"
            )
            XCTAssertTrue(handlers.contains { ($0["timeout"] as? Int) == 5 })
            XCTAssertNil(handlers.first?["hooks"], "Cursor uses direct command entries, not matcher groups")
        }

        await manager.uninstall()

        XCTAssertEqual(manager.status, .notInstalled)
        let removed = try Self.readJSON(at: hooksURL)
        XCTAssertEqual(removed["theme"] as? String, "preserve")
        let remainingHooks = try XCTUnwrap(removed["hooks"] as? [String: Any])
        let remainingPreTool = try XCTUnwrap(remainingHooks["preToolUse"] as? [[String: Any]])
        XCTAssertEqual(remainingPreTool.first?["command"] as? String, "echo existing")
        XCTAssertEqual(remainingHooks.keys.sorted(), ["preToolUse"])
    }

    @MainActor
    func testOpenCodeInstallWritesOwnedGlobalPluginAndRemovesOnlyThatFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pluginsURL = fixture.home.appendingPathComponent(".config/opencode/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsURL, withIntermediateDirectories: true)
        let siblingURL = pluginsURL.appendingPathComponent("existing.js")
        try Data("export const Existing = async () => ({})\n".utf8).write(to: siblingURL)
        let pluginURL = pluginsURL.appendingPathComponent("agentnotch.js")

        let manager = fixture.manager(provider: .openCode)
        await manager.install()
        await manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        XCTAssertNil(manager.lastError)
        XCTAssertNotNil(manager.trustInstructions)
        let source = String(decoding: try Data(contentsOf: pluginURL), as: UTF8.self)
        XCTAssertTrue(source.contains("// Managed by Agent Notch."))
        XCTAssertTrue(source.contains("export const AgentNotchPlugin"))
        XCTAssertTrue(source.contains("Bun.spawn"))
        XCTAssertTrue(source.contains(manager.installedRelayURL.path))
        XCTAssertTrue(source.contains("\"--provider\", \"opencode\""))
        if let bunURL = Self.executableURL(named: "bun") {
            let encodedPluginURL = try JSONEncoder().encode(pluginURL.absoluteString)
            let pluginLiteral = String(decoding: encodedPluginURL, as: UTF8.self)
            let process = Process()
            process.executableURL = bunURL
            process.arguments = [
                "-e",
                "const module = await import(\(pluginLiteral)); const hooks = await module.AgentNotchPlugin({ directory: '/tmp' }); if (typeof hooks.event !== 'function') process.exit(1)",
            ]
            let errors = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, errorText)
        }
        let permissions = try FileManager.default.attributesOfItem(atPath: pluginURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        await manager.uninstall()

        XCTAssertEqual(manager.status, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: siblingURL.path))
    }

    @MainActor
    func testOpenCodeInstallRefusesToOverwriteUnownedPlugin() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pluginURL = fixture.home.appendingPathComponent(".config/opencode/plugins/agentnotch.js")
        try FileManager.default.createDirectory(
            at: pluginURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let original = Data("export const CustomPlugin = async () => ({})\n".utf8)
        try original.write(to: pluginURL)

        let manager = fixture.manager(provider: .openCode)
        await manager.install()

        XCTAssertEqual(manager.status, .unavailable("Installation failed"))
        XCTAssertEqual(try Data(contentsOf: pluginURL), original)
        XCTAssertTrue(manager.lastError?.contains("will not replace") == true)
    }

    @MainActor
    func testIntegratedProvidersDeclareAnExplicitTimeoutUnit() {
        for provider in IntegratedHookProvider.allCases {
            let timeout = provider.timeout(for: "SessionStart")
            XCTAssertEqual(timeout.unit, provider.timeoutUnit)
        }
        XCTAssertEqual(IntegratedHookProvider.geminiCLI.timeout(for: "BeforeAgent"), .milliseconds(5_000))
        XCTAssertEqual(IntegratedHookProvider.codex.timeout(for: "SessionEnd"), .seconds(3))
        XCTAssertEqual(IntegratedHookProvider.claudeCode.timeout(for: "PermissionRequest"), .seconds(5))
    }

    func testHandlerIdentityCollapsesOwnedLegacyAndCurrent() {
        let relay = HookRelayIdentity(
            provider: .claudeCode,
            relayURL: URL(fileURLWithPath: "/tmp/agentnotch-hook")
        )
        let current = relay.commandHandler(
            timeout: .seconds(5),
            claudeExecForm: true,
            eventName: "SessionStart"
        )
        let legacy: [String: Any] = [
            "type": "command",
            "command": relay.relayURL.path,
            "args": ["--provider", "claude-code"],
            "timeout": 5,
        ]
        let foreign: [String: Any] = ["command": "echo existing"]

        XCTAssertEqual(relay.identity(of: current, eventName: "SessionStart"), .current)
        XCTAssertEqual(relay.identity(of: legacy, eventName: "SessionStart"), .legacy)
        XCTAssertEqual(relay.identity(of: foreign, eventName: "SessionStart"), .none)
    }

    @MainActor
    func testGeminiIntegrationWritesOfficialHookNamesAndMillisecondTimeouts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let manager = fixture.manager(provider: .geminiCLI)
        await manager.install()

        XCTAssertEqual(manager.status, .awaitingFirstEvent)
        let settingsURL = fixture.home.appendingPathComponent(".gemini/settings.json")
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

    private static func executableURL(named name: String) -> URL? {
        let paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        return paths
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
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
        bundledRelay = root.appendingPathComponent("bundle/agentnotch-hook")
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
    func manager(provider: AgentProvider, answersFromNotch: Bool = false) -> ProviderIntegrationManager {
        ProviderIntegrationManager(
            provider: provider,
            homeDirectoryURL: home,
            bundledRelayURL: bundledRelay,
            answersFromNotch: { answersFromNotch }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
