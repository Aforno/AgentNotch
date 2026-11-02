import Foundation

/// Cursor hook quirks. `sessionStart` fires as soon as the CLI or a composer
/// opens, and closing the terminal skips `sessionEnd`, so an interactive start
/// is not work yet. Headless `agent -p` runs never fire `beforeSubmitPrompt`
/// or `stop`, so their start is the only live signal.
public enum CursorEventPolicy {
    /// `AgentHookPayload.source` the relay stamps on a headless sessionStart.
    public static let headlessSource = "print"

    /// Marks a sessionStart from `agent -p`/`--print` so it stays visible.
    /// `agentArguments` is the agent process's argv when the relay can read it.
    public static func markHeadlessStart(
        _ payload: inout AgentHookPayload,
        agentArguments: [String]?
    ) {
        guard HookEventName(rawEventName: payload.hookEventName) == .sessionStart,
              let agentArguments,
              agentArguments.dropFirst().contains(where: isPrintFlag)
        else { return }
        payload.source = headlessSource
    }

    private static func isPrintFlag(_ argument: String) -> Bool {
        argument == "-p" || argument == "--print" || argument.hasPrefix("--print=")
    }
}
