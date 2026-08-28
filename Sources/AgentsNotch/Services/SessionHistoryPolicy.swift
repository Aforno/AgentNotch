import Foundation

enum SessionHistoryPolicy {
    static let maximumCompletedSessionRetentionDays = 7

    /// Existing preferences may contain older 30, 90, or 365-day choices.
    /// Keep honoring shorter positive values, but never retain beyond seven days.
    static func completedSessionRetentionAge(configuredDays: Int?) -> TimeInterval? {
        guard let configuredDays else { return nil }
        let days = min(max(1, configuredDays), maximumCompletedSessionRetentionDays)
        return TimeInterval(days * 24 * 60 * 60)
    }
}
