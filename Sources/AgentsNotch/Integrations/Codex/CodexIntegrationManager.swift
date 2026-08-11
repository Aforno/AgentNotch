import AgentsNotchCore
import Foundation
import Observation

enum ProviderIntegrationStatus: Equatable {
    /// Hooks / relay are not present on disk.
    case notInstalled
    /// Hooks are installed; no genuine provider event has been observed yet.
    case awaitingFirstEvent
    /// At least one genuine provider event was received while hooks were installed.
    case connected
    case unavailable(String)

    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .awaitingFirstEvent: "Awaiting first event"
        case .connected: "Connected"
        case let .unavailable(message): message
        }
    }

    var canInstall: Bool {
        switch self {
        case .notInstalled, .unavailable: true
        case .awaitingFirstEvent, .connected: false
        }
    }
}

@Observable
@MainActor
final class ProviderIntegrationManager {
    let provider: AgentProvider
    private(set) var status: ProviderIntegrationStatus = .notInstalled
    private(set) var lastError: String?
    /// Remembers that a real (non-self-test) provider event has been observed.
    /// Survives refresh while hooks remain installed so Connected is not
    /// demoted by a no-op status recompute. Cleared when hooks disappear or
    /// on uninstall so reinstall cannot falsely report Connected.
    private(set) var hasReceivedEvent = false

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

    /// Provider-specific guidance shown while an observer is installed but not
    /// yet verified by a live event.
    var trustInstructions: String? {
        guard status == .awaitingFirstEvent else { return nil }
        return switch provider {
        case .codex:
            "Open /hooks in Codex once to review and trust the installed lifecycle hooks."
        case .openCode:
            "Restart OpenCode after installing the plugin, then start a new session."
        default:
            nil
        }
    }

    /// Recomputes install health from disk. Pass `hasReceivedEvent: true` when the runtime
    /// already observed a genuine event for this provider (e.g. Settings refresh).
    func refreshStatus(hasReceivedEvent knownEvent: Bool = false) {
        if knownEvent {
            hasReceivedEvent = true
        }
        lastError = nil
        guard fileManager.isExecutableFile(atPath: installedRelayURL.path),
              hookConfigurationContainsRelay()
        else {
            // Hooks/relay gone (manual removal or uninstall). Drop sticky
            // verification so a later install() cannot report Connected
            // without a post-reinstall event.
            hasReceivedEvent = false
            status = .notInstalled
            return
        }
        status = hasReceivedEvent ? .connected : .awaitingFirstEvent
    }

    /// Promote to Connected after a genuine provider event (not self-test).
    func noteEventReceived() {
        switch status {
        case .awaitingFirstEvent, .connected:
            hasReceivedEvent = true
            status = .connected
        case .notInstalled, .unavailable:
            // Do not sticky-set while uninstalled; reinstall must await a new event.
            break
        }
    }

    func prepareForMonitoring() {
        refreshStatus()
        guard status != .notInstalled else { return }

        do {
            try updateInstalledRelayIfNeeded()
            try updateOpenCodePluginIfNeeded()
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Integration update failed")
        }
    }

    func install() {
        do {
            try writeBundledRelay()
            try installHookConfiguration()
            status = hasReceivedEvent ? .connected : .awaitingFirstEvent
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Installation failed")
        }
    }

    func uninstall() {
        do {
            try removeHookConfiguration()
            hasReceivedEvent = false
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
        case .cursor:
            ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse", "postToolUseFailure", "stop", "sessionEnd"]
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
        if provider == .openCode {
            try removeOpenCodePlugin()
            return
        }
        if provider == .cursor {
            try removeCursorHookConfiguration()
            return
        }

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

    private func installCursorHookConfiguration() throws {
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
            handlers.removeAll { handler in
                guard let command = handler["command"] as? String else { return false }
                return isAgentsNotchCommand(command)
            }
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

    private func removeCursorHookConfiguration() throws {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return }
        let configuration = try readRootConfiguration()
        var root = configuration.root
        guard root["hooks"] != nil else { return }
        var hooks = try hooksDictionary(in: root)

        for eventName in Array(hooks.keys) {
            guard var handlers = hooks[eventName] as? [[String: Any]] else { continue }
            handlers.removeAll { handler in
                guard let command = handler["command"] as? String else { return false }
                return isAgentsNotchCommand(command)
            }
            if handlers.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = handlers
            }
        }

        root["hooks"] = hooks
        try writeRootConfiguration(root, expectedData: configuration.originalData)
    }

    private func installOpenCodePlugin() throws {
        let currentData = fileManager.fileExists(atPath: hooksURL.path)
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

    private func removeOpenCodePlugin() throws {
        guard fileManager.fileExists(atPath: hooksURL.path) else { return }
        let data = try Data(contentsOf: hooksURL)
        guard isOwnedOpenCodePlugin(data) else { return }
        try fileManager.removeItem(at: hooksURL)
    }

    private func updateOpenCodePluginIfNeeded() throws {
        guard provider == .openCode,
              fileManager.fileExists(atPath: hooksURL.path)
        else { return }
        let currentData = try Data(contentsOf: hooksURL)
        guard isOwnedOpenCodePlugin(currentData), currentData != openCodePluginData else { return }
        try writeOpenCodePlugin(expectedData: currentData)
    }

    private func writeOpenCodePlugin(expectedData: Data?) throws {
        let destination = hooksURL.resolvingSymlinksInPath()
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
        try openCodePluginData.write(to: destination, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
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
                return handlers.contains { handler in
                    guard let command = handler["command"] as? String else { return false }
                    return isAgentsNotchCommand(command)
                }
            }
        }
        return eventNames.allSatisfy { eventName in
            let groups = hooks[eventName] as? [[String: Any]] ?? []
            return groups.contains(where: groupContainsAgentsNotchHandler)
        }
    }

    private func isOwnedOpenCodePlugin(_ data: Data) -> Bool {
        let source = String(decoding: data, as: UTF8.self)
        return source.contains(Self.openCodePluginMarker)
            && source.contains("export const AgentsNotchPlugin")
    }

    private static let openCodePluginMarker = "// Managed by Agents Notch."

    private var openCodePluginData: Data {
        let relayPath = installedRelayURL.path
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let encodedRelayPath = try? encoder.encode(relayPath)
        let relayLiteral = encodedRelayPath.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        let source = """
        \(Self.openCodePluginMarker)
        // Reinstall from Agents Notch instead of editing this generated bridge.
        const relayPath = \(relayLiteral)

        const emit = async (payload) => {
          if (!payload?.session_id) return
          try {
            const process = Bun.spawn([relayPath, "--provider", "opencode"], {
              stdin: new Blob([JSON.stringify(payload)]),
              stdout: "ignore",
              stderr: "ignore",
            })
            await process.exited
          } catch {
            // Monitoring is passive and must never interrupt OpenCode.
          }
        }

        const textFromParts = (parts) => (parts ?? [])
          .filter((part) => part?.type === "text" && typeof part.text === "string")
          .map((part) => part.text)
          .join("\\n")

        const errorMessage = (error) => error?.data?.message ?? error?.message ?? String(error ?? "OpenCode session failed")

        export const AgentsNotchPlugin = async ({ directory }) => ({
          event: async ({ event }) => {
            const properties = event?.properties ?? {}
            const info = properties.info ?? {}
            const sessionID = properties.sessionID ?? info.id
            const cwd = info.directory ?? directory

            switch (event?.type) {
              case "session.created":
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: "SessionStart",
                  timestamp: info.time?.created,
                  parent_session_id: info.parentID,
                })
                break
              case "session.status":
                if (properties.status?.type === "busy") {
                  await emit({ session_id: sessionID, cwd, hook_event_name: "UserPromptSubmit" })
                }
                break
              case "session.idle":
                await emit({ session_id: sessionID, cwd, hook_event_name: "Stop" })
                break
              case "session.error":
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: "StopFailure",
                  error: errorMessage(properties.error),
                })
                break
              case "permission.replied":
                const permissionReply = properties.reply ?? properties.response
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: permissionReply === "reject" || permissionReply === "deny"
                    ? "PermissionDenied"
                    : "UserPromptSubmit",
                })
                break
              case "question.asked":
                await emit({
                  session_id: sessionID,
                  cwd,
                  hook_event_name: "Notification",
                  notification_type: "agent_needs_input",
                  message: properties.questions?.[0]?.question ?? "OpenCode needs input",
                })
                break
              case "question.replied":
              case "question.rejected":
                await emit({ session_id: sessionID, cwd, hook_event_name: "UserPromptSubmit" })
                break
              case "message.part.updated":
                if (properties.part?.type === "tool" && properties.part.state?.status === "error") {
                  await emit({
                    session_id: sessionID ?? properties.part.sessionID,
                    cwd,
                    hook_event_name: "PostToolUseFailure",
                    tool_name: properties.part.tool,
                    tool_input: properties.part.state.input,
                    error: properties.part.state.error,
                    timestamp: properties.part.state.time?.end,
                  })
                }
                break
            }
          },
          "chat.message": async (input, output) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "UserPromptSubmit",
              prompt: textFromParts(output.parts),
            })
          },
          "permission.ask": async (input) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "PermissionRequest",
              tool_name: input.type ?? input.permission ?? input.title,
              tool_input: input.metadata,
              timestamp: input.time?.created,
            })
          },
          "tool.execute.before": async (input, output) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "PreToolUse",
              tool_name: input.tool,
              tool_input: output.args,
            })
          },
          "tool.execute.after": async (input) => {
            await emit({
              session_id: input.sessionID,
              cwd: directory,
              hook_event_name: "PostToolUse",
              tool_name: input.tool,
              tool_input: input.args,
            })
          },
        })
        """
        return Data((source + "\n").utf8)
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
