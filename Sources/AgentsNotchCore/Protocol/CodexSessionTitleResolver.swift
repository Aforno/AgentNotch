import Foundation

/// Codex keeps a generated conversation title in `session_index.jsonl`.
/// Prompt hooks only carry the latest user message, so this bounded index
/// read is the allowed disk walk for titles. It does not invent sessions.
public enum CodexSessionTitleResolver {
    public static func title(
        forNativeSessionId sessionId: String,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
    ) -> String? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeSessionID(trimmed) else { return nil }

        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexURL), !data.isEmpty else { return nil }

        var found: String?
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["id"] as? String == trimmed
            else { continue }
            found = object["thread_name"] as? String ?? object["threadName"] as? String
        }
        return found.flatMap(AgentTaskTitle.displayable)
    }

    public static func threadID(fromCanonicalSessionID sessionID: String) -> String? {
        let prefix = "\(AgentProvider.codex.rawValue):"
        guard sessionID.hasPrefix(prefix) else { return nil }
        let remainder = String(sessionID.dropFirst(prefix.count))
        return remainder.split(separator: ":").first.map(String.init)
    }

    private static func isSafeSessionID(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("\n")
            && !value.contains("\0")
            && !value.contains("/")
            && !value.contains("\\")
    }
}
