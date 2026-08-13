public enum GrokHookRouting {
    /// Grok also loads Claude- and Cursor-compatible hooks. When the native
    /// Agents Notch observer is installed, those compatibility callbacks are
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
}
