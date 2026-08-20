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
    let answersFromNotch: Bool

    init(provider: AgentProvider, relayURL: URL, answersFromNotch: Bool = false) {
        self.provider = provider
        self.relayURL = relayURL
        self.answersFromNotch = answersFromNotch
    }

    var quotedCommand: String {
        let path = relayURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let providerName = provider.rawValue.replacingOccurrences(of: "'", with: "'\\''")
        var command = "'\(path)' --provider '\(providerName)'"
        if answersFromNotch {
            command += " --answer"
        }
        return command
    }

    func identity(of handler: [String: Any], eventName: String = "SessionStart") -> HookHandlerIdentity {
        guard isOwned(handler) else { return .none }
        return isCurrent(handler, eventName: eventName) ? .current : .legacy
    }

    func commandHandler(
        timeout: HookTimeout,
        claudeExecForm: Bool,
        eventName: String
    ) -> [String: Any] {
        let resolvedTimeout = waitTimeout(timeout, eventName: eventName)
        if claudeExecForm {
            let blocking = answersFromNotch && AgentReplyPolicy.waitsForAnswer(eventName: eventName)
            return [
                "type": "command",
                "command": relayURL.path,
                "args": commandArguments(),
                "timeout": resolvedTimeout.jsonValue,
                "async": !blocking,
            ]
        }
        return [
            "type": "command",
            "command": quotedCommand,
            "timeout": resolvedTimeout.jsonValue,
        ]
    }

    func cursorHandler(timeout: HookTimeout, eventName: String) -> [String: Any] {
        [
            "command": quotedCommand,
            "timeout": waitTimeout(timeout, eventName: eventName).jsonValue,
        ]
    }

    private func commandArguments() -> [String] {
        var arguments = ["--provider", provider.rawValue]
        if answersFromNotch {
            arguments.append("--answer")
        }
        return arguments
    }

    private func waitTimeout(_ timeout: HookTimeout, eventName: String) -> HookTimeout {
        guard answersFromNotch, AgentReplyPolicy.waitsForAnswer(eventName: eventName) else {
            return timeout
        }
        switch timeout.unit {
        case .seconds:
            return .seconds(AgentReplyPolicy.waitSeconds)
        case .milliseconds:
            return .milliseconds(AgentReplyPolicy.waitSeconds * 1_000)
        }
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

    private func isCurrent(_ handler: [String: Any], eventName: String) -> Bool {
        let args = handler["args"] as? [String] ?? []
        let command = handler["command"] as? String ?? ""
        let hasAnswerFlag = args.contains("--answer") || command.contains(" --answer")
        guard hasAnswerFlag == answersFromNotch else { return false }
        guard provider == .claudeCode else { return true }
        let expectedAsync = !(answersFromNotch && AgentReplyPolicy.waitsForAnswer(eventName: eventName))
        return handler["type"] as? String == "command"
            && handler["async"] as? Bool == expectedAsync
            && handler["command"] as? String == relayURL.path
            && args == commandArguments()
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
