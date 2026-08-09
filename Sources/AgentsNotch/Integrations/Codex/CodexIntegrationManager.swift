import AgentsNotchCore
import Foundation
import Observation

enum ProviderIntegrationStatus: Equatable {
    case notInstalled
    case installedNeedsTrust
    case ready
    case unavailable(String)

    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .installedNeedsTrust: "Installed · review hooks"
        case .ready: "Installed"
        case let .unavailable(message): message
        }
    }

    var canInstall: Bool {
        switch self {
        case .notInstalled, .unavailable: true
        case .installedNeedsTrust, .ready: false
        }
    }
}

@Observable
@MainActor
final class ProviderIntegrationManager {
    let provider: AgentProvider
    private(set) var status: ProviderIntegrationStatus = .notInstalled
    private(set) var lastError: String?

    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let bundledRelayURLOverride: URL?

    init(
        provider: AgentProvider,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil,
        bundledRelayURL: URL? = nil
    ) {
        self.provider = provider
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        bundledRelayURLOverride = bundledRelayURL
        refreshStatus()
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

    var trustInstructions: String? {
        switch provider {
        case .codex: "Open /hooks in Codex once to review and trust the installed lifecycle hooks."
        case .claudeCode: "Open /hooks in Claude Code to inspect the installed lifecycle hooks."
        case .grok: "Open /hooks in Grok to inspect the installed lifecycle hooks."
        case .geminiCLI: "Open /hooks panel in Gemini CLI to inspect the installed lifecycle hooks."
        default: nil
        }
    }

    func refreshStatus() {
        lastError = nil
        guard fileManager.isExecutableFile(atPath: installedRelayURL.path),
              hookConfigurationContainsRelay()
        else {
            status = .notInstalled
            return
        }
        status = provider == .codex ? .installedNeedsTrust : .ready
    }

    func prepareForMonitoring() {
        refreshStatus()
        guard status != .notInstalled else { return }

        do {
            try updateInstalledRelayIfNeeded()
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Relay update failed")
        }
    }

    func install() {
        do {
            try writeBundledRelay()
            try installHookConfiguration()
            status = provider == .codex ? .installedNeedsTrust : .ready
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Installation failed")
        }
    }

    func uninstall() {
        do {
            try removeHookConfiguration()
            status = .notInstalled
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Removal failed")
        }
    }

    private var hooksURL: URL {
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
        default:
            homeDirectoryURL
                .appendingPathComponent(".agentsnotch/integrations", isDirectory: true)
                .appendingPathComponent("\(provider.rawValue).json")
        }
    }

    private var eventNames: [String] {
        switch provider {
        case .codex:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .claudeCode:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .grok:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .geminiCLI:
            ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        default:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]
        }
    }

    private var quotedCommand: String {
        let path = installedRelayURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let providerName = provider.rawValue.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(path)' --provider '\(providerName)'"
    }

    private struct RootConfiguration {
        var root: [String: Any]
        let originalData: Data?
    }

    private func readRootConfiguration() throws -> RootConfiguration {
        guard fileManager.fileExists(atPath: hooksURL.path) else {
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

    private func installHookConfiguration() throws {
        let configuration = try readRootConfiguration()
        var root = configuration.root
        var hooks = try hooksDictionary(in: root)

        for eventName in eventNames {
            let newGroup: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": quotedCommand,
                    "timeout": hookTimeout(for: eventName),
                ]],
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

    private func removeHookConfiguration() throws {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return }
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

    private func hooksDictionary(in root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw ProviderIntegrationError.invalidHooksSection(hooksURL.path)
        }
        return hooks
    }

    private func writeRootConfiguration(_ root: [String: Any], expectedData: Data?) throws {
        let destination = hooksURL.resolvingSymlinksInPath()
        let existingPermissions = (try? fileManager.attributesOfItem(atPath: destination.path))?[.posixPermissions]
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let currentData = fileManager.fileExists(atPath: destination.path)
            ? try Data(contentsOf: destination)
            : nil
        guard currentData == expectedData else {
            throw ProviderIntegrationError.configurationChanged(hooksURL.path)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: existingPermissions ?? 0o600],
            ofItemAtPath: destination.path
        )
    }

    private func hookConfigurationContainsRelay() -> Bool {
        guard let configuration = try? readRootConfiguration(),
              let hooks = try? hooksDictionary(in: configuration.root)
        else { return false }
        return eventNames.allSatisfy { eventName in
            let groups = hooks[eventName] as? [[String: Any]] ?? []
            return groups.contains(where: groupContainsAgentsNotchHandler)
        }
    }

    /// Drops only Agents Notch handlers from a matcher group. Returns nil when the
    /// group has no handlers left so install/uninstall can remove empty groups.
    private func removeAgentsNotchHandlers(from group: [String: Any]) -> [String: Any]? {
        guard var handlers = group["hooks"] as? [[String: Any]] else { return group }
        handlers.removeAll { handler in
            guard let command = handler["command"] as? String else { return false }
            return isAgentsNotchCommand(command)
        }
        guard !handlers.isEmpty else { return nil }
        var updated = group
        updated["hooks"] = handlers
        return updated
    }

    private func groupContainsAgentsNotchHandler(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { handler in
            guard let command = handler["command"] as? String else { return false }
            return isAgentsNotchCommand(command)
        }
    }

    /// True when `command` invokes the installed relay binary (as the executable),
    /// not merely mentions its path in an echo/logging string.
    private func isAgentsNotchCommand(_ command: String) -> Bool {
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

    private func commandStartsWithExecutable(_ command: String, executable: String) -> Bool {
        guard command.hasPrefix(executable) else { return false }
        let rest = command.dropFirst(executable.count)
        return rest.isEmpty || rest.first?.isWhitespace == true
    }

    private func hookTimeout(for eventName: String) -> Int {
        if provider == .codex { return CodexHookConfiguration.timeout(for: eventName) }
        if provider == .geminiCLI { return 5_000 }
        return 5
    }

    private func updateInstalledRelayIfNeeded() throws {
        guard let bundledRelayURL,
              fileManager.isExecutableFile(atPath: bundledRelayURL.path)
        else { throw ProviderIntegrationError.relayMissing }

        let bundledData = try Data(contentsOf: bundledRelayURL)
        let installedData = try Data(contentsOf: installedRelayURL)
        guard bundledData != installedData else { return }
        try writeBundledRelay(data: bundledData)
    }

    private func writeBundledRelay(data: Data? = nil) throws {
        guard let bundledRelayURL,
              fileManager.isExecutableFile(atPath: bundledRelayURL.path)
        else { throw ProviderIntegrationError.relayMissing }

        try fileManager.createDirectory(
            at: installedRelayURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: installedRelayURL.deletingLastPathComponent().path
        )
        let relayData = try data ?? Data(contentsOf: bundledRelayURL)
        try relayData.write(to: installedRelayURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedRelayURL.path)
    }
}

private enum ProviderIntegrationError: LocalizedError {
    case relayMissing
    case invalidHooksFile(String)
    case invalidHooksSection(String)
    case invalidHookEvent(String, String)
    case configurationChanged(String)
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
        case .incompleteInstallation:
            "One or more required lifecycle hooks could not be installed."
        }
    }
}
