import Foundation

/// Codex keeps a generated conversation title in `session_index.jsonl`.
/// Prompt hooks only carry the latest user message, so this bounded index
/// read is the allowed disk walk for titles. It does not invent sessions.
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
        guard let data = indexTail(at: indexURL), !data.isEmpty else { return nil }

        var found: String?
        for line in data.split(separator: 0x0A) {
            guard let record = try? JSONDecoder().decode(SessionIndexRecord.self, from: Data(line)),
                  record.id == trimmed
            else { continue }
            found = record.threadName
        }
        return found.flatMap(AgentTaskTitle.displayable)
    }

    private static func indexTail(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let endOffset = try? handle.seekToEnd() else { return nil }
        let maximumBytes = UInt64(maximumIndexTailBytes)
        let startOffset = endOffset > maximumBytes ? endOffset - maximumBytes : 0
        let readOffset = startOffset > 0 ? startOffset - 1 : 0
        let readCount = Int(endOffset - readOffset)
        guard (try? handle.seek(toOffset: readOffset)) != nil,
              var data = try? handle.read(upToCount: readCount),
              !data.isEmpty
        else {
            return nil
        }

        if startOffset > 0 {
            if data.first == 0x0A {
                data.removeFirst()
            } else if let newline = data.firstIndex(of: 0x0A) {
                data.removeSubrange(data.startIndex...newline)
            } else {
                return nil
            }
        }
        return data
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

private extension KeyedDecodingContainer {
    /// Missing keys and non-string values are absent. Does not fail the record.
    func lossyString(forKeys keys: Key...) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
