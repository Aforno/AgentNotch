import Foundation

/// Titles derived from provider prompts. Grok wraps the visible user message in
/// `<user_query>` tags, so the first raw line is often the tag itself. Follow-up
/// turns may send only an image placeholder.
public enum AgentTaskTitle {
    public static let untitled = "Untitled task"

    public static func fromPrompt(_ prompt: String, limit: Int = 140) -> String? {
        let source = unwrapUserQuery(prompt)
        let line = source
            .split(whereSeparator: \.isNewline)
            .map { stripLeadingUserQueryTag(String($0)) }
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
