import Foundation

extension Data {
    private static let newline = Data([0x0A])

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
