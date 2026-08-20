import Foundation

/// Grok hook quirks: skipped SessionStart, parent-scoped subagents, on-disk
/// workflow publish, and `<user_query>` prompt unwrapping.
public enum GrokEventPolicy {
    /// Grok emits SessionStart for non-agent commands such as `grok --version`,
    /// then exits without a matching SessionEnd.
    public static let shouldMapSessionStart = false

    public static func remapsParentScopedSubagent(
        provider: AgentProvider,
        payload: AgentHookPayload,
        parentSessionId: String?
    ) -> Bool {
        provider == .grok
            && payload.agentId?.nonEmpty == nil
            && parentSessionId == nil
    }

    public static func shouldPublishWorkflowState(_ payload: AgentHookPayload) -> Bool {
        switch HookEventName(rawEventName: payload.hookEventName) {
        case .subagentStart, .subagentStop, .sessionEnd, .stop:
            return true
        default:
            return payload.toolName?.lowercased() == "workflow"
        }
    }

    public static func shouldResolveSessionContext(_ payload: AgentHookPayload) -> Bool {
        if shouldPublishWorkflowState(payload) { return true }
        if HookEventName(rawEventName: payload.hookEventName) == .userPromptSubmit {
            return true
        }
        if payload.parentSessionId?.nonEmpty != nil { return false }
        return true
    }

    /// Inner text of Grok's `<user_query>` wrapper, with leftover tags stripped
    /// from each line. Generic title cleanup still happens in `AgentTaskTitle`.
    public static func visiblePrompt(_ prompt: String) -> String {
        unwrapUserQuery(prompt)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { stripLeadingUserQueryTag(String($0)) }
            .joined(separator: "\n")
    }

    private static func unwrapUserQuery(_ prompt: String) -> String {
        let open = "<user_query>"
        let close = "</user_query>"
        guard let openRange = prompt.range(of: open, options: .caseInsensitive),
              let closeRange = prompt.range(
                of: close,
                options: .caseInsensitive,
                range: openRange.upperBound..<prompt.endIndex
              )
        else { return prompt }
        return String(prompt[openRange.upperBound..<closeRange.lowerBound])
    }

    private static func stripLeadingUserQueryTag(_ line: String) -> String {
        let prefixes = ["<user_query>", "</user_query>"]
        for prefix in prefixes {
            if line.count >= prefix.count,
               line.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame
            {
                return String(line.dropFirst(prefix.count))
            }
        }
        return line
    }
}
