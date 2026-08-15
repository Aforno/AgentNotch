import AgentsNotchCore
import Foundation

enum HookHandlerIdentity: Equatable, Sendable {
    case none
    case legacy
    case current

    var isOwned: Bool { self != .none }
}

struct HookRelayIdentity: Sendable {
    let provider: AgentProvider
    let relayURL: URL

    var quotedCommand: String {
        let path = relayURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let providerName = provider.rawValue.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(path)' --provider '\(providerName)'"
    }

    func identity(of handler: [String: Any]) -> HookHandlerIdentity {
        guard isOwned(handler) else { return .none }
        return isCurrent(handler) ? .current : .legacy
    }

    func commandHandler(timeout: HookTimeout, claudeExecForm: Bool) -> [String: Any] {
        if claudeExecForm {
            return [
                "type": "command",
                "command": relayURL.path,
                "args": ["--provider", provider.rawValue],
                "timeout": timeout.jsonValue,
                "async": true,
            ]
        }
        return [
            "type": "command",
            "command": quotedCommand,
            "timeout": timeout.jsonValue,
        ]
    }

    func cursorHandler(timeout: HookTimeout) -> [String: Any] {
        [
            "command": quotedCommand,
            "timeout": timeout.jsonValue,
        ]
    }

    private func isOwned(_ handler: [String: Any]) -> Bool {
        if let command = handler["command"] as? String, isAgentsNotchCommand(command) {
            return true
        }
        guard let command = handler["command"] as? String else { return false }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == relayURL.path else { return false }
        let args = handler["args"] as? [String] ?? []
        if let index = args.firstIndex(of: "--provider"), args.indices.contains(index + 1) {
            return args[index + 1] == provider.rawValue
        }
        return provider == .codex && !args.contains("--provider")
    }

    private func isCurrent(_ handler: [String: Any]) -> Bool {
        guard provider == .claudeCode else { return true }
        let args = handler["args"] as? [String] ?? []
        return handler["type"] as? String == "command"
            && handler["async"] as? Bool == true
            && handler["command"] as? String == relayURL.path
            && args == ["--provider", provider.rawValue]
    }

    /// True when `command` invokes the installed relay binary (as the executable),
    /// not merely mentions its path in an echo/logging string.
    private func isAgentsNotchCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == quotedCommand { return true }

        let path = relayURL.path
        let quotedPath = "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
        for executable in [quotedPath, path] where commandStartsWithExecutable(trimmed, executable: executable) {
            let remainder = String(trimmed.dropFirst(executable.count))
            let providerForms = [
                "--provider '\(provider.rawValue)'",
                "--provider \"\(provider.rawValue)\"",
                "--provider \(provider.rawValue)",
            ]
            if providerForms.contains(where: remainder.contains) { return true }
            return provider == .codex && !remainder.contains("--provider")
        }
        return false
    }

    private func commandStartsWithExecutable(_ command: String, executable: String) -> Bool {
        guard command.hasPrefix(executable) else { return false }
        let rest = command.dropFirst(executable.count)
        return rest.isEmpty || rest.first?.isWhitespace == true
    }
}
