import Foundation

public enum GrokHookRouting {
    /// Grok also loads Claude- and Cursor-compatible hooks. When the native
    /// Agent Notch observer is installed, those compatibility callbacks are
    /// duplicates and must remain completely passive.
    public static func shouldSkipClaudeCompatibilityHook(
        grokHookEvent: String?,
        configuredProvider: AgentProvider,
        hasNativeRelay: Bool
    ) -> Bool {
        grokHookEvent != nil
            && (configuredProvider == .claudeCode || configuredProvider == .cursor)
            && hasNativeRelay
    }

    /// Legacy Codex hook commands omit `--provider`. Grok sets `GROK_HOOK_EVENT`
    /// and may invoke Claude/Cursor compatibility hooks that must be attributed
    /// to Grok so they are not mislabeled.
    public static func resolvedProvider(
        explicit: AgentProvider?,
        grokHookEvent: String?
    ) -> AgentProvider {
        let resolved = explicit ?? (grokHookEvent == nil ? .codex : .grok)
        if grokHookEvent != nil, resolved == .claudeCode || resolved == .cursor {
            return .grok
        }
        return resolved
    }

    public static func configurationContainsNativeRelay(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"]
        else { return false }
        return containsNativeRelay(hooks)
    }

    private static func containsNativeRelay(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if let command = object["command"] as? String,
               command.contains("/.agentnotch/bin/agentnotch-hook"),
               ["--provider 'grok'", "--provider \"grok\"", "--provider grok"]
                .contains(where: command.contains)
            {
                return true
            }
            return object.values.contains(where: containsNativeRelay)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsNativeRelay)
        }
        return false
    }
}
