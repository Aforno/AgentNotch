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
        default:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"]
        }
    }

    private var quotedCommand: String {
        let path = installedRelayURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let providerName = provider.rawValue.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(path)' --provider '\(providerName)'"
    }

    private func readRootConfiguration() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return [:] }
        let data = try Data(contentsOf: hooksURL)
        guard !data.isEmpty else { return [:] }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderIntegrationError.invalidHooksFile(hooksURL.path)
        }
        return root
    }

    private func installHookConfiguration() throws {
        var root = try readRootConfiguration()
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventName in eventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            groups.removeAll(where: isAgentsNotchGroup)
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": quotedCommand,
                    "timeout": hookTimeout(for: eventName),
                ]],
            ])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        try writeRootConfiguration(root)
    }

    private func removeHookConfiguration() throws {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return }
        var root = try readRootConfiguration()
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventName in eventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            groups.removeAll(where: isAgentsNotchGroup)
            if groups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = groups
            }
        }
        root["hooks"] = hooks
        try writeRootConfiguration(root)
    }

    private func writeRootConfiguration(_ root: [String: Any]) throws {
        let destination = hooksURL.resolvingSymlinksInPath()
        let existingPermissions = (try? fileManager.attributesOfItem(atPath: destination.path))?[.posixPermissions]
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: existingPermissions ?? 0o600],
            ofItemAtPath: destination.path
        )
    }

    private func hookConfigurationContainsRelay() -> Bool {
        guard let root = try? readRootConfiguration(),
              let hooks = root["hooks"] as? [String: Any]
        else { return false }
        return eventNames.allSatisfy { eventName in
            let groups = hooks[eventName] as? [[String: Any]] ?? []
            return groups.contains(where: isAgentsNotchGroup)
        }
    }

    private func isAgentsNotchGroup(_ group: [String: Any]) -> Bool {
        guard let handlers = group["hooks"] as? [[String: Any]] else { return false }
        return handlers.contains { handler in
            guard let command = handler["command"] as? String else { return false }
            return command.contains(installedRelayURL.path)
        }
    }

    private func hookTimeout(for eventName: String) -> Int {
        provider == .codex ? CodexHookConfiguration.timeout(for: eventName) : 5
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

    var errorDescription: String? {
        switch self {
        case .relayMissing:
            "The bundled agent relay could not be found. Launch the packaged Agents Notch app."
        case let .invalidHooksFile(path):
            "The existing \(path) file is not a JSON object."
        }
    }
}
