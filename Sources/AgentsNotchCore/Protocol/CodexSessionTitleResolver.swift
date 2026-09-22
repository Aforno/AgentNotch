import Foundation

/// Looks up Codex conversation titles in the tail of `session_index.jsonl`.
public enum CodexSessionTitleResolver {
    public static let maximumIndexTailBytes = 4 * 1_024 * 1_024

    public static func title(
        forNativeSessionId sessionId: String,
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
    ) -> String? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeSessionID(trimmed) else { return nil }

        let indexURL = codexHome.appendingPathComponent("session_index.jsonl")
        guard let data = Data.jsonlTail(at: indexURL, maxBytes: maximumIndexTailBytes),
              !data.isEmpty
        else { return nil }

        // The index is append-only, so the newest matching record wins.
        let candidates = Self.prefilterBytes(for: trimmed).map(data.lines(containing:))
            ?? data.split(separator: 0x0A)
        let decoder = JSONDecoder()
        for line in candidates.reversed() {
            guard let record = try? decoder.decode(SessionIndexRecord.self, from: Data(line)),
                  record.id == trimmed
            else { continue }
            return record.threadName.flatMap(AgentTaskTitle.displayable)
        }
        return nil
    }

    /// The ID's raw bytes, or nil when JSON might escape it.
    private static func prefilterBytes(for sessionId: String) -> Data? {
        let bytes = Data(sessionId.utf8)
        let isVerbatim = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F && $0 != UInt8(ascii: "\"") }
        return isVerbatim ? bytes : nil
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

private struct SessionIndexRecord: Decodable {
    let id: String?
    let threadName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName
        case thread_name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lossyString(forKeys: .id)
        // Prefer the historical snake_case spelling when both aliases exist.
        threadName = container.lossyString(forKeys: .thread_name, .threadName)
    }
}
