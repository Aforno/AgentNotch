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
        guard let data = indexTail(at: indexURL), !data.isEmpty else { return nil }

        // The index is append-only, so the newest matching record wins. Scan
        // backwards and decode only lines that mention the ID: splitting and
        // decoding a full 4 MiB tail costs ~60 ms on the hook's critical path.
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

    /// IDs JSON never escapes appear verbatim in their record. Anything else
    /// falls back to decoding every line.
    private static func prefilterBytes(for sessionId: String) -> Data? {
        let bytes = Data(sessionId.utf8)
        let isVerbatim = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F && $0 != UInt8(ascii: "\"") }
        return isVerbatim ? bytes : nil
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
            } else if let newline = data.firstNewline {
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
