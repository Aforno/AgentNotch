import AgentsNotchCore
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let arguments = CommandLine.arguments
let configuredProvider: AgentProvider = {
    if let index = arguments.firstIndex(of: "--provider"), arguments.indices.contains(index + 1) {
        return AgentProvider(rawValue: arguments[index + 1])
    }
    return .codex
}()
let provider: AgentProvider = ProcessInfo.processInfo.environment["GROK_HOOK_EVENT"] == nil
    ? configuredProvider
    : .grok
let grokNativeConfiguration = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".grok/hooks/agentsnotch.json")
let grokHasNativeRelay = (try? String(contentsOf: grokNativeConfiguration, encoding: .utf8))?
    .contains(".agentsnotch/bin/agentsnotch-hook") == true
let isDuplicateClaudeCompatibilityHook = provider == .grok
    && configuredProvider == .claudeCode
    && grokHasNativeRelay

do {
    let payload = try JSONDecoder().decode(AgentHookPayload.self, from: input)
    if !isDuplicateClaudeCompatibilityHook,
       let event = AgentHookEventMapper.map(payload, provider: provider)
    {
        try? UnixSocketClient.send(event)
    }
    // Some providers inspect hook stdout. An empty object is always passive.
    FileHandle.standardOutput.write(Data("{}\n".utf8))
} catch {
    // Monitoring must never interrupt the agent. All providers treat exit 0 as success.
    FileHandle.standardOutput.write(Data("{}\n".utf8))
}
