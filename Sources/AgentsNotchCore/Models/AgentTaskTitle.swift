import Foundation

/// Generic title cleanup: drop empty values, image placeholders, markup tags,
/// system prompts, and housekeeping text. Provider prompt unwrapping happens
/// before this runs.
public enum AgentTaskTitle {
    public static let untitled = "Untitled task"

    public static func fromPrompt(_ prompt: String, limit: Int = 140) -> String? {
        let line = prompt
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(displayable)
            .first ?? ""
        return concise(line, limit: limit)
    }

    public static func displayable(_ task: String) -> String? {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != untitled else { return nil }
        guard !isMarkupTag(trimmed) else { return nil }
        guard !isHousekeeping(trimmed) else { return nil }
        let stripped = strippingImagePlaceholders(trimmed)
        guard !stripped.isEmpty, !isMarkupTag(stripped) else { return nil }
        if stripped.lowercased().hasPrefix("you are ") { return nil }
        return stripped
    }

    public static func isHousekeeping(_ task: String) -> Bool {
        let lowered = task.lowercased()
        return lowered.contains("memory writing agent")
            || lowered.contains("<in-app-browser-context")
    }

    /// Codex can start short-lived helper sessions for app-owned work. They
    /// remain in history for diagnostics but should not appear as user tasks.
    public static func isInternalHelper(_ task: String, provider: AgentProvider) -> Bool {
        provider == .codex
            && task.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix(commitMessageHelperPrefix)
    }

    /// Official Codex thread titles can replace the helper prompt. Classify
    /// from any retained task text so the row stays hidden.
    public static func isInternalHelper(_ session: AgentSession) -> Bool {
        if isInternalHelper(session.task, provider: session.provider) {
            return true
        }
        return session.recentEvents.contains { event in
            guard let task = event.task else { return false }
            return isInternalHelper(task, provider: session.provider)
        }
    }

    /// Keep the first real title. Later prompts may be `[Image #1]` or a short
    /// follow-up; SessionStart repo names are placeholders and may be replaced.
    public static func assigned(
        current: String,
        incoming: String?,
        projectName: String? = nil
    ) -> String {
        if let incoming, isHousekeeping(incoming) {
            return displayable(current) ?? incoming
        }
        guard let incoming = incoming.flatMap(displayable) else {
            return displayable(current) ?? current
        }
        if displayable(current) == nil { return incoming }
        if let projectName, current == projectName { return incoming }
        return current
    }

    private static let commitMessageHelperPrefix =
        "using the supplied git context below, generate a git commit message"

    private static func strippingImagePlaceholders(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[Image #\d+\]"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMarkupTag(_ text: String) -> Bool {
        text.range(of: #"^</?[A-Za-z][A-Za-z0-9_-]*(?:\s[^>]*)?>$"#, options: .regularExpression) != nil
    }

    private static func concise(_ text: String, limit: Int) -> String? {
        guard !text.isEmpty else { return nil }
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}
