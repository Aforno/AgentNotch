public enum GrokHookRouting {
    /// Grok also loads Claude-compatible hooks. When the native Agents Notch
    /// observer is installed, the compatibility callback is a duplicate and
    /// must remain completely passive.
    public static func shouldSkipClaudeCompatibilityHook(
        grokHookEvent: String?,
        configuredProvider: AgentProvider,
        hasNativeRelay: Bool
    ) -> Bool {
        grokHookEvent != nil
            && configuredProvider == .claudeCode
            && hasNativeRelay
    }
}
