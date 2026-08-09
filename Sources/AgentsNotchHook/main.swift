import AgentsNotchCore
import Darwin
import Foundation

let input = (try? FileHandle.standardInput.read(upToCount: AgentHookInput.maximumBytes + 1)) ?? Data()
let arguments = CommandLine.arguments
let explicitProvider: AgentProvider? = {
    if let index = arguments.firstIndex(of: "--provider"), arguments.indices.contains(index + 1) {
        return AgentProvider(rawValue: arguments[index + 1])
    }
    return nil
}()
let configuredProvider = explicitProvider ?? .codex
let provider: AgentProvider = explicitProvider
    ?? (ProcessInfo.processInfo.environment["GROK_HOOK_EVENT"] == nil ? .codex : .grok)
let socketURL: URL = {
    if let index = arguments.firstIndex(of: "--socket"), arguments.indices.contains(index + 1) {
        return URL(fileURLWithPath: arguments[index + 1])
    }
    return AgentSocketLocation.defaultURL
}()
let isSelfTest = arguments.contains("--self-test")
let grokNativeConfiguration = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".grok/hooks/agentsnotch.json")
let grokHasNativeRelay = configurationContainsNativeGrokRelay(at: grokNativeConfiguration)
let isDuplicateClaudeCompatibilityHook = ProcessInfo.processInfo.environment["GROK_HOOK_EVENT"] != nil
    && configuredProvider == .claudeCode
    && grokHasNativeRelay

do {
    var payload = try AgentHookInput.decode(input)
    let grokContext = provider == .grok
        ? GrokSessionContextResolver.resolve(payload)
        : nil
    if let grokContext {
        payload.parentSessionId = grokContext.parentSessionId ?? payload.parentSessionId
        payload.description = grokContext.agentRole ?? payload.description
    }
    if !isDuplicateClaudeCompatibilityHook,
       var event = AgentHookEventMapper.map(payload, provider: provider)
    {
        event.origin = hookOrigin()
        if isSelfTest {
            var metadata = event.metadata ?? [:]
            metadata["source"] = "self-test"
            event.metadata = metadata
        }
        if let rawURL = ProcessInfo.processInfo.environment["AGENTS_NOTCH_APPLICATION_URL"] {
            event.applicationURL = URL(string: rawURL)
        }
        try? UnixSocketClient.send(event, to: socketURL)
    }
    if !isDuplicateClaudeCompatibilityHook,
       provider == .grok,
       shouldPublishWorkflowState(payload),
       var workflowEvent = grokContext?.workflowEvent(
           now: Date(),
           workingDirectory: payload.workspaceRoot ?? payload.cwd
       )
    {
        // Stop/SessionEnd already sent a completed event. On-disk workflow status
        // is often still active/running; do not reopen the session with a later
        // Date()-stamped running activity. Keep the workflowUpdate snapshot for UI.
        if isTerminalLifecycleHook(payload), workflowEvent.resolvedState.isActive {
            workflowEvent.type = .completed
            workflowEvent.state = .completed
        }
        if isSelfTest {
            var metadata = workflowEvent.metadata ?? [:]
            metadata["source"] = "self-test"
            workflowEvent.metadata = metadata
        }
        try? UnixSocketClient.send(workflowEvent, to: socketURL)
    }
    // Some providers inspect hook stdout. An empty object is always passive.
    FileHandle.standardOutput.write(Data("{}\n".utf8))
} catch {
    // Monitoring must never interrupt the agent. All providers treat exit 0 as success.
    FileHandle.standardOutput.write(Data("{}\n".utf8))
}

private func hookOrigin() -> AgentOrigin? {
    let environment = ProcessInfo.processInfo.environment
    let terminalProgram = environment["TERM_PROGRAM"]
    let bundleIdentifier = environment["AGENTS_NOTCH_BUNDLE_IDENTIFIER"]
        ?? environment["__CFBundleIdentifier"]
        ?? terminalProgram.flatMap(bundleIdentifier(forTerminalProgram:))
    let sessionIdentifier = environment["TERM_SESSION_ID"]
        ?? environment["ITERM_SESSION_ID"]
        ?? environment["WEZTERM_PANE"]
        ?? environment["KITTY_WINDOW_ID"]
    let origin = AgentOrigin(
        bundleIdentifier: bundleIdentifier?.nonEmpty,
        processIdentifier: getppid(),
        terminalProgram: terminalProgram?.nonEmpty,
        terminalSessionIdentifier: sessionIdentifier?.nonEmpty,
        tty: environment["TTY"]?.nonEmpty
    )
    return origin.isEmpty ? nil : origin
}

private func bundleIdentifier(forTerminalProgram program: String) -> String? {
    switch program.lowercased() {
    case "apple_terminal": "com.apple.Terminal"
    case "iterm.app": "com.googlecode.iterm2"
    case "vscode": "com.microsoft.VSCode"
    case "warpterminal": "dev.warp.Warp-Stable"
    case "wezterm": "com.github.wez.wezterm"
    case "ghostty": "com.mitchellh.ghostty"
    default: nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func configurationContainsNativeGrokRelay(at url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hooks = root["hooks"]
    else { return false }
    return containsNativeGrokRelay(hooks)
}

private func containsNativeGrokRelay(_ value: Any) -> Bool {
    if let object = value as? [String: Any] {
        if let command = object["command"] as? String,
           command.contains("/.agentsnotch/bin/agentsnotch-hook"),
           ["--provider 'grok'", "--provider \"grok\"", "--provider grok"]
            .contains(where: command.contains)
        {
            return true
        }
        return object.values.contains(where: containsNativeGrokRelay)
    }
    if let array = value as? [Any] {
        return array.contains(where: containsNativeGrokRelay)
    }
    return false
}

private func shouldPublishWorkflowState(_ payload: AgentHookPayload) -> Bool {
    let event = payload.hookEventName.replacingOccurrences(of: "_", with: "").lowercased()
    if ["subagentstart", "subagentstop", "sessionend", "stop"].contains(event) {
        return true
    }
    return payload.toolName?.lowercased() == "workflow"
}

private func isTerminalLifecycleHook(_ payload: AgentHookPayload) -> Bool {
    let event = payload.hookEventName.replacingOccurrences(of: "_", with: "").lowercased()
    return ["stop", "stopfailure", "sessionend"].contains(event)
}
