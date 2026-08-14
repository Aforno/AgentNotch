import AgentsNotchCore
import Foundation

struct MonitoringPreparation: Sendable {
    let isInstalled: Bool
    let error: String?
}

final class ProviderFileSystem: @unchecked Sendable {
    let manager: FileManager
    /// Every provider shares the installed relay path, so disk maintenance must
    /// be serialized across manager instances as well as within one provider.
    private static let lock = NSLock()

    init(_ manager: FileManager) {
        self.manager = manager
    }

    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try operation()
    }
}

/// Shared relay path plus the per-config-shape install strategy.
struct ProviderHookStore: Sendable {
    let provider: AgentProvider
    let fileSystem: ProviderFileSystem
    let homeDirectoryURL: URL
    private let bundledRelayURLOverride: URL?

    init(
        provider: AgentProvider,
        fileSystem: ProviderFileSystem,
        homeDirectoryURL: URL,
        bundledRelayURL: URL?
    ) {
        self.provider = provider
        self.fileSystem = fileSystem
        self.homeDirectoryURL = homeDirectoryURL
        bundledRelayURLOverride = bundledRelayURL
    }

    var installedRelayURL: URL {
        homeDirectoryURL
            .appendingPathComponent(".agentsnotch/bin", isDirectory: true)
            .appendingPathComponent("agentsnotch-hook")
    }

    var bundledRelayURL: URL? {
        if let bundledRelayURLOverride {
            return bundledRelayURLOverride
        }
        return Bundle.main.resourceURL?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("agentsnotch-hook")
    }

    func prepareForMonitoringOnDisk() -> MonitoringPreparation {
        fileSystem.withLock {
            guard fileSystem.manager.isExecutableFile(atPath: installedRelayURL.path),
                  hookConfigurationLooksInstalled()
            else {
                return MonitoringPreparation(isInstalled: false, error: nil)
            }
            do {
                try updateInstalledRelayIfNeeded()
                try updateOpenCodePluginIfNeeded()
                try updateHookConfigurationIfNeeded()
                return MonitoringPreparation(isInstalled: true, error: nil)
            } catch {
                return MonitoringPreparation(isInstalled: true, error: error.localizedDescription)
            }
        }
    }

    func install() throws {
        try fileSystem.withLock {
            try writeBundledRelay()
            try installHookConfiguration()
        }
    }

    func uninstall() throws {
        try fileSystem.withLock {
            try removeHookConfiguration()
        }
    }

    func looksInstalled() -> Bool {
        fileSystem.manager.isExecutableFile(atPath: installedRelayURL.path)
            && hookConfigurationLooksInstalled()
    }

    nonisolated private var hooksURL: URL {
        switch provider {
        case .codex:
            homeDirectoryURL
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json")
        case .claudeCode:
            homeDirectoryURL
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json")
        case .grok:
            homeDirectoryURL
                .appendingPathComponent(".grok/hooks", isDirectory: true)
                .appendingPathComponent("agentsnotch.json")
        case .geminiCLI:
            homeDirectoryURL
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("settings.json")
        case .openCode:
            homeDirectoryURL
                .appendingPathComponent(".config/opencode/plugins", isDirectory: true)
                .appendingPathComponent("agentsnotch.js")
        case .cursor:
            homeDirectoryURL
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("hooks.json")
        default:
            homeDirectoryURL
                .appendingPathComponent(".agentsnotch/integrations", isDirectory: true)
                .appendingPathComponent("\(provider.rawValue).json")
        }
    }

    nonisolated private var eventNames: [String] {
        switch provider {
        case .codex:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .claudeCode:
            [
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
        case .grok:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .geminiCLI:
            ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        case .cursor:
            ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse", "postToolUseFailure", "stop", "sessionEnd"]
        default:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]
        }
    }

    nonisolated private var quotedCommand: String {
        let path = installedRelayURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let providerName = provider.rawValue.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(path)' --provider '\(providerName)'"
    }

    private struct RootConfiguration {
        var root: [String: Any]
        let originalData: Data?
    }

    nonisolated private func readRootConfiguration() throws -> RootConfiguration {
        guard fileSystem.manager.fileExists(atPath: hooksURL.path) else {
            return RootConfiguration(root: [:], originalData: nil)
        }
        let data = try Data(contentsOf: hooksURL)
        guard !data.isEmpty else {
            return RootConfiguration(root: [:], originalData: data)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderIntegrationError.invalidHooksFile(hooksURL.path)
        }
        return RootConfiguration(root: root, originalData: data)
    }

    nonisolated private func installHookConfiguration() throws {
        if provider == .openCode {
            try installOpenCodePlugin()
            return
        }
        if provider == .cursor {
            try installCursorHookConfiguration()
            return
        }

        let configuration = try readRootConfiguration()
        var root = configuration.root
        var hooks = try hooksDictionary(in: root)

        for eventName in eventNames {
            let newGroup: [String: Any] = [
                "hooks": [commandHookHandler(for: eventName)],
            ]
            if hooks[eventName] == nil {
                hooks[eventName] = [newGroup]
                continue
            }
            guard var groups = hooks[eventName] as? [[String: Any]] else {
                throw ProviderIntegrationError.invalidHookEvent(eventName, hooksURL.path)
            }
            groups = groups.compactMap { removeAgentsNotchHandlers(from: $0) }
            groups.append(newGroup)
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        try writeRootConfiguration(root, expectedData: configuration.originalData)
        guard hookConfigurationContainsRelay() else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    nonisolated private func removeHookConfiguration() throws {
        if provider == .openCode {
            try removeOpenCodePlugin()
            return
        }
        if provider == .cursor {
            try removeCursorHookConfiguration()
            return
        }

        guard fileSystem.manager.fileExists(atPath: hooksURL.path) else { return }
        let configuration = try readRootConfiguration()
        var root = configuration.root
        guard root["hooks"] != nil else { return }
        var hooks = try hooksDictionary(in: root)

        // Scan every event key so uninstall also removes provider-owned hooks
        // written by an older Agents Notch event schema.
        for eventName in Array(hooks.keys) {
            // Non-array event values are left intact; never delete the key on cast failure.
            guard var groups = hooks[eventName] as? [[String: Any]] else { continue }
            groups = groups.compactMap { removeAgentsNotchHandlers(from: $0) }
            if groups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = groups
            }
        }
        root["hooks"] = hooks
        try writeRootConfiguration(root, expectedData: configuration.originalData)
    }

    nonisolated private func installCursorHookConfiguration() throws {
        let configuration = try readRootConfiguration()
        var root = configuration.root
        var hooks = try hooksDictionary(in: root)

        for eventName in eventNames {
            let handler: [String: Any] = [
                "command": quotedCommand,
                "timeout": hookTimeout(for: eventName),
            ]
            guard var handlers = hooks[eventName] as? [[String: Any]] ?? (hooks[eventName] == nil ? [] : nil) else {
                throw ProviderIntegrationError.invalidHookEvent(eventName, hooksURL.path)
            }
            handlers.removeAll(where: isAgentsNotchHandler)
            handlers.append(handler)
            hooks[eventName] = handlers
        }

        root["version"] = root["version"] ?? 1
        root["hooks"] = hooks
        try writeRootConfiguration(root, expectedData: configuration.originalData)
        guard hookConfigurationContainsRelay() else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    nonisolated private func removeCursorHookConfiguration() throws {
        guard fileSystem.manager.fileExists(atPath: hooksURL.path) else { return }
        let configuration = try readRootConfiguration()
        var root = configuration.root
        guard root["hooks"] != nil else { return }
        var hooks = try hooksDictionary(in: root)

        for eventName in Array(hooks.keys) {
            guard var handlers = hooks[eventName] as? [[String: Any]] else { continue }
            handlers.removeAll(where: isAgentsNotchHandler)
            if handlers.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = handlers
            }
        }

        root["hooks"] = hooks
        try writeRootConfiguration(root, expectedData: configuration.originalData)
    }

    nonisolated private func installOpenCodePlugin() throws {
        let currentData = fileSystem.manager.fileExists(atPath: hooksURL.path)
            ? try Data(contentsOf: hooksURL)
            : nil
        if let currentData, !isOwnedOpenCodePlugin(currentData) {
            throw ProviderIntegrationError.existingOpenCodePlugin(hooksURL.path)
        }
        try writeOpenCodePlugin(expectedData: currentData)
        guard hookConfigurationContainsRelay() else {
            throw ProviderIntegrationError.incompleteInstallation
        }
    }

    nonisolated private func removeOpenCodePlugin() throws {
        guard fileSystem.manager.fileExists(atPath: hooksURL.path) else { return }
        let data = try Data(contentsOf: hooksURL)
        guard isOwnedOpenCodePlugin(data) else { return }
        try fileSystem.manager.removeItem(at: hooksURL)
    }

    nonisolated private func updateOpenCodePluginIfNeeded() throws {
        guard provider == .openCode,
              fileSystem.manager.fileExists(atPath: hooksURL.path)
        else { return }
        let currentData = try Data(contentsOf: hooksURL)
        guard isOwnedOpenCodePlugin(currentData), currentData != openCodePluginData else { return }
        try writeOpenCodePlugin(expectedData: currentData)
    }

    nonisolated private func writeOpenCodePlugin(expectedData: Data?) throws {
        let destination = hooksURL.resolvingSymlinksInPath()
        try fileSystem.manager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let currentData = fileSystem.manager.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination)
            : nil
        guard currentData == expectedData else {
            throw ProviderIntegrationError.configurationChanged(hooksURL.path)
        }
        try openCodePluginData.write(to: destination, options: .atomic)
        try fileSystem.manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    nonisolated private func hooksDictionary(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw ProviderIntegrationError.invalidHooksSection(hooksURL.path)
        }
        return hooks
    }

    nonisolated private func writeRootConfiguration(_ root: [String: Any], expectedData: Data?) throws {
        let destination = hooksURL.resolvingSymlinksInPath()
        let existingPermissions = (try? fileSystem.manager.attributesOfItem(atPath: destination.path))?[.posixPermissions]
        try fileSystem.manager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let currentData = fileSystem.manager.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination)
            : nil
        guard currentData == expectedData else {
            throw ProviderIntegrationError.configurationChanged(hooksURL.path)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination, options: .atomic)
        try fileSystem.manager.setAttributes(
            [.posixPermissions: existingPermissions ?? 0o600],
            ofItemAtPath: destination.path
        )
    }

    nonisolated private func hookConfigurationContainsRelay() -> Bool {
        if provider == .openCode {
            guard let data = try? Data(contentsOf: hooksURL), isOwnedOpenCodePlugin(data) else {
                return false
            }
            let source = String(decoding: data, as: UTF8.self)
            return source.contains(installedRelayURL.path) && source.contains("--provider\", \"opencode")
        }

        guard let configuration = try? readRootConfiguration(),
              let hooks = try? hooksDictionary(in: configuration.root)
        else { return false }
        if provider == .cursor {
            return eventNames.allSatisfy { eventName in
                let handlers = hooks[eventName] as? [[String: Any]] ?? []
                return handlers.contains(where: isAgentsNotchHandler)
            }
        }
        return eventNames.allSatisfy { eventName in
            let groups = hooks[eventName] as? [[String: Any]] ?? []
            return groups.contains { groupContainsCurrentAgentsNotchHandler($0) }
        }
    }

    /// True when any installed hook still belongs to this provider, including
    /// an older schema that is missing newly documented lifecycle events.
    nonisolated private func hookConfigurationLooksInstalled() -> Bool {
        if provider == .openCode {
            return hookConfigurationContainsRelay()
        }
        return hookConfigurationContainsRelay() || hookConfigurationHasAnyAgentsNotchHandler()
    }

    nonisolated private func hookConfigurationHasAnyAgentsNotchHandler() -> Bool {
        guard let configuration = try? readRootConfiguration(),
              let hooks = try? hooksDictionary(in: configuration.root)
        else { return false }
        if provider == .cursor {
            return hooks.values.contains { value in
                let handlers = value as? [[String: Any]] ?? []
                return handlers.contains(where: isAgentsNotchHandler)
            }
        }
        return hooks.values.contains { value in
            let groups = value as? [[String: Any]] ?? []
            return groups.contains(where: groupContainsAgentsNotchHandler)
        }
    }

    nonisolated private func updateHookConfigurationIfNeeded() throws {
        guard provider != .openCode, !hookConfigurationContainsRelay() else { return }
        try installHookConfiguration()
    }

    /// Claude Code documents exec-form `command` + `args`, with `timeout` in
    /// seconds and `async` on the command handler. Agents Notch only observes
    /// lifecycle events, so its handlers run asynchronously: Claude Code does
    /// not wait for them and ignores any control-oriented output.
    nonisolated private func commandHookHandler(for eventName: String) -> [String: Any] {
        if provider == .claudeCode {
            return [
                "type": "command",
                "command": installedRelayURL.path,
                "args": ["--provider", provider.rawValue],
                "timeout": hookTimeout(for: eventName),
                "async": true,
            ]
        }
        return [
            "type": "command",
            "command": quotedCommand,
            "timeout": hookTimeout(for: eventName),
        ]
    }

    nonisolated private func isOwnedOpenCodePlugin(_ data: Data) -> Bool {
        OpenCodePluginTemplate.isOwned(data)
    }

    nonisolated private var openCodePluginData: Data {
        OpenCodePluginTemplate.data(relayURL: installedRelayURL)
    }

    /// Drops only Agents Notch handlers from a matcher group. Returns nil when the
    /// group has no handlers left so install/uninstall can remove empty groups.
    nonisolated private func removeAgentsNotchHandlers(from group: [String: Any]) -> [String: Any]? {
        guard var handlers = group["hooks"] as? [[String: Any]] else { return group }
        handlers.removeAll(where: isAgentsNotchHandler)
        guard !handlers.isEmpty else { return nil }
        var updated = group
        updated["hooks"] = handlers
        return updated
    }

    nonisolated private func groupContainsAgentsNotchHandler(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains(where: isAgentsNotchHandler)
    }

    nonisolated private func groupContainsCurrentAgentsNotchHandler(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains(where: isCurrentAgentsNotchHandler)
    }

    nonisolated private func isCurrentAgentsNotchHandler(_ handler: [String: Any]) -> Bool {
        guard isAgentsNotchHandler(handler) else { return false }
        guard provider == .claudeCode else { return true }
        let args = handler["args"] as? [String] ?? []
        return handler["type"] as? String == "command"
            && handler["async"] as? Bool == true
            && handler["command"] as? String == installedRelayURL.path
            && args == ["--provider", provider.rawValue]
    }

    /// Matches the installed relay in shell form (`'path' --provider 'x'`) or
    /// Claude Code exec form (`command` + `args`).
    nonisolated private func isAgentsNotchHandler(_ handler: [String: Any]) -> Bool {
        if let command = handler["command"] as? String, isAgentsNotchCommand(command) {
            return true
        }
        guard let command = handler["command"] as? String else { return false }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == installedRelayURL.path else { return false }
        let args = handler["args"] as? [String] ?? []
        if let index = args.firstIndex(of: "--provider"), args.indices.contains(index + 1) {
            return args[index + 1] == provider.rawValue
        }
        return provider == .codex && !args.contains("--provider")
    }

    /// True when `command` invokes the installed relay binary (as the executable),
    /// not merely mentions its path in an echo/logging string.
    nonisolated private func isAgentsNotchCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == quotedCommand { return true }

        let path = installedRelayURL.path
        let quotedPath = "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
        for executable in [quotedPath, path] where commandStartsWithExecutable(trimmed, executable: executable) {
            let remainder = String(trimmed.dropFirst(executable.count))
            let providerForms = [
                "--provider '\(provider.rawValue)'",
                "--provider \"\(provider.rawValue)\"",
                "--provider \(provider.rawValue)",
            ]
            if providerForms.contains(where: remainder.contains) { return true }
            // Older helpers omitted --provider and therefore used the Codex default.
            return provider == .codex && !remainder.contains("--provider")
        }
        return false
    }

    nonisolated private func commandStartsWithExecutable(_ command: String, executable: String) -> Bool {
        guard command.hasPrefix(executable) else { return false }
        let rest = command.dropFirst(executable.count)
        return rest.isEmpty || rest.first?.isWhitespace == true
    }

    nonisolated private func hookTimeout(for eventName: String) -> Int {
        if provider == .codex { return CodexHookConfiguration.timeout(for: eventName) }
        if provider == .geminiCLI { return 5_000 }
        return 5
    }

    nonisolated private func updateInstalledRelayIfNeeded() throws {
        guard let bundledRelayURL,
              fileSystem.manager.isExecutableFile(atPath: bundledRelayURL.path)
        else { throw ProviderIntegrationError.relayMissing }

        let bundledData = try Data(contentsOf: bundledRelayURL)
        let installedData = try Data(contentsOf: installedRelayURL)
        guard bundledData != installedData else { return }
        try writeBundledRelay(data: bundledData)
    }

    nonisolated private func writeBundledRelay(data: Data? = nil) throws {
        guard let bundledRelayURL,
              fileSystem.manager.isExecutableFile(atPath: bundledRelayURL.path)
        else { throw ProviderIntegrationError.relayMissing }

        try fileSystem.manager.createDirectory(
            at: installedRelayURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileSystem.manager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: installedRelayURL.deletingLastPathComponent().path
        )
        let relayData = try data ?? Data(contentsOf: bundledRelayURL)
        try relayData.write(to: installedRelayURL, options: .atomic)
        try fileSystem.manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedRelayURL.path)
    }
}

private enum ProviderIntegrationError: LocalizedError {
    case relayMissing
    case invalidHooksFile(String)
    case invalidHooksSection(String)
    case invalidHookEvent(String, String)
    case configurationChanged(String)
    case existingOpenCodePlugin(String)
    case incompleteInstallation

    var errorDescription: String? {
        switch self {
        case .relayMissing:
            "The bundled agent relay could not be found. Launch the packaged Agents Notch app."
        case let .invalidHooksFile(path):
            "The existing \(path) file is not a JSON object."
        case let .invalidHooksSection(path):
            "The existing hooks value in \(path) is not a JSON object."
        case let .invalidHookEvent(event, path):
            "The existing \(event) hooks in \(path) are not an array."
        case let .configurationChanged(path):
            "\(path) changed while Agents Notch was updating it. Try again."
        case let .existingOpenCodePlugin(path):
            "Agents Notch will not replace the existing OpenCode plugin at \(path)."
        case .incompleteInstallation:
            "One or more required lifecycle hooks could not be installed."
        }
    }
}
