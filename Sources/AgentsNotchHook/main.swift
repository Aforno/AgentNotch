import AgentsNotchCore
import Darwin
import Foundation

let input = readHookInput()
let arguments = CommandLine.arguments
let explicitProvider: AgentProvider? = {
    if let index = arguments.firstIndex(of: "--provider"), arguments.indices.contains(index + 1) {
        return AgentProvider(rawValue: arguments[index + 1])
    }
    return nil
}()
let configuredProvider = explicitProvider ?? .codex
let grokHookEvent = ProcessInfo.processInfo.environment["GROK_HOOK_EVENT"]
// Grok can execute Claude settings hooks (--provider claude-code). Attribute
// those to Grok so Claude-only installs do not mislabel Grok activity.
let provider: AgentProvider = {
    let resolved = explicitProvider
        ?? (grokHookEvent == nil ? .codex : .grok)
    if grokHookEvent != nil, resolved == .claudeCode {
        return .grok
    }
    return resolved
}()
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
let isDuplicateClaudeCompatibilityHook = GrokHookRouting.shouldSkipClaudeCompatibilityHook(
    grokHookEvent: grokHookEvent,
    configuredProvider: configuredProvider,
    hasNativeRelay: grokHasNativeRelay
)

if isDuplicateClaudeCompatibilityHook {
    // Drain stdin above, then stop before decoding or walking Grok's session tree.
    writePassiveResponse()
    exit(EXIT_SUCCESS)
}

do {
    var payload = try AgentHookInput.decode(input)
    // Skip the Grok session-tree walk on high-frequency tool hooks when the
    // payload already has hierarchy and we do not need on-disk workflow state.
    let grokContext: GrokSessionContext?
    if provider == .grok, shouldResolveGrokSessionContext(payload) {
        grokContext = GrokSessionContextResolver.resolve(payload)
    } else {
        grokContext = nil
    }
    if let grokContext {
        payload.parentSessionId = grokContext.parentSessionId ?? payload.parentSessionId
        payload.description = grokContext.agentRole ?? payload.description
    }
    let permissionRequestRequiresUserInput = provider != .codex
        || CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload)
    if var event = AgentHookEventMapper.map(
        payload,
        provider: provider,
        permissionRequestRequiresUserInput: permissionRequestRequiresUserInput
    )
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
    if provider == .grok,
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
    writePassiveResponse()
} catch {
    // Monitoring must never interrupt the agent. All providers treat exit 0 as success.
    writePassiveResponse()
}

private func writePassiveResponse() {
    FileHandle.standardOutput.write(Data("{}\n".utf8))
}

/// Reads stdin up to the safety cap and drains any remainder so an oversized
/// provider payload cannot observe EPIPE mid-write.
private func readHookInput() -> Data {
    let handle = FileHandle.standardInput
    let cap = AgentHookInput.maximumBytes + 1
    var data = (try? handle.read(upToCount: cap)) ?? Data()
    if data.count >= cap {
        // Cap exceeded (or exactly filled the probe). Consume the rest of the
        // pipe so the writer finishes cleanly; the decoder will still reject.
        while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
            // discard
        }
        if data.count > AgentHookInput.maximumBytes {
            data = data.prefix(AgentHookInput.maximumBytes + 1)
        }
    }
    return data
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

/// Whether this Grok hook needs the on-disk session-tree walk.
/// High-frequency PreToolUse/PostToolUse with hierarchy already present and
/// no workflow publish requirement skip the unbounded FS scan.
private func shouldResolveGrokSessionContext(_ payload: AgentHookPayload) -> Bool {
    if shouldPublishWorkflowState(payload) { return true }
    // Parent already known and no workflow publish: skip the tree walk.
    if payload.parentSessionId?.nonEmpty != nil { return false }
    // Otherwise resolve so children can attach (own-directory short-circuit
    // keeps top-level parent tool hooks cheap).
    return true
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
    return ["stop", "stopfailure", "sessionend", "afteragent"].contains(event)
}
