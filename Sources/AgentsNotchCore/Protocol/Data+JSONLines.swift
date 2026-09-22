import Foundation

extension Data {
    private static let newline = Data([0x0A])

    /// Complete records in the last `maxBytes` of a JSONL file. Reads one byte
    /// before the cut so a record starting exactly at the cut is kept, and
    /// never reads past the end offset seen at open, even if the writer appends.
    /// Returns nil when the file is unreadable or the tail is one partial record.
    package static func jsonlTail(at url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let endOffset = try? handle.seekToEnd() else { return nil }
        let maximumBytes = UInt64(maxBytes)
        let startOffset = endOffset > maximumBytes ? endOffset - maximumBytes : 0
        let readOffset = startOffset > 0 ? startOffset - 1 : 0
        guard (try? handle.seek(toOffset: readOffset)) != nil,
              var data = try? handle.read(upToCount: Int(endOffset - readOffset)),
              !data.isEmpty
        else {
            return nil
        }

        if startOffset > 0 {
            guard let newline = data.firstNewline else { return nil }
            data.removeSubrange(data.startIndex...newline)
        }
        return data
    }

    /// Offset of the first newline. `Data.range(of:)` is a fast memory search;
    /// the generic `firstIndex(of:)` walks multi-megabyte records byte by byte.
    package var firstNewline: Index? {
        range(of: Self.newline)?.lowerBound
    }

    /// Newline-delimited records containing `needle`, oldest first. Used by the
    /// hook relay to scan multi-megabyte JSONL tails: splitting and decoding
    /// every record costs tens of milliseconds on the agent's critical path.
    /// A hit is only a candidate; callers still verify the decoded record.
    /// `needle` must be non-empty and must not contain a newline.
    package func lines(containing needle: Data) -> [Data] {
        var lines: [Data] = []
        var cursor = startIndex
        while cursor < endIndex, let hit = range(of: needle, in: cursor..<endIndex) {
            let start = range(of: Self.newline, options: .backwards, in: cursor..<hit.lowerBound)?
                .upperBound ?? cursor
            let end = range(of: Self.newline, in: hit.upperBound..<endIndex)?.lowerBound ?? endIndex
            lines.append(self[start..<end])
            cursor = end + 1
        }
        return lines
    }
}
