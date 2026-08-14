import Foundation

extension String {
    /// Whitespace-only strings are absent for hook fields, titles, and paths.
    package var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
