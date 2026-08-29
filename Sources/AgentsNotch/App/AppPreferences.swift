import Foundation

/// Owns the persisted preference names and the defaults registered at launch.
enum AppPreferences {
    enum Key {
        static let animationsEnabled = "animationsEnabled"
        static let answerFromNotchEnabled = "answerFromNotchEnabled"
        static let attentionNotificationSoundEnabled = "attentionNotificationSoundEnabled"
        static let attentionNotificationsEnabled = "attentionNotificationsEnabled"
        static let automaticallyCheckForUpdates = "automaticallyCheckForUpdates"
        static let debugMode = "debugMode"
        static let displayPreference = "displayPreference"
        static let failureNotificationsEnabled = "failureNotificationsEnabled"
        static let globalActivityShortcut = "globalActivityShortcut"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let historyRetentionDays = "historyRetentionDays"
        static let notchEnabled = "notchEnabled"
        static let privacyModeEnabled = "privacyModeEnabled"
        static let showVirtualNotch = "showVirtualNotch"
    }

    static var registeredDefaults: [String: Any] {
        var values: [String: Any] = [
            Key.animationsEnabled: true,
            Key.answerFromNotchEnabled: false,
            Key.attentionNotificationSoundEnabled: false,
            Key.attentionNotificationsEnabled: false,
            Key.automaticallyCheckForUpdates: true,
            Key.displayPreference: DisplayPreference.primary.rawValue,
            Key.failureNotificationsEnabled: false,
            Key.globalActivityShortcut: GlobalActivityShortcut.off.rawValue,
            Key.hasCompletedOnboarding: false,
            Key.historyRetentionDays: SessionHistoryPolicy.maximumCompletedSessionRetentionDays,
            Key.notchEnabled: true,
            Key.privacyModeEnabled: false,
            Key.showVirtualNotch: false,
        ]
        #if DEBUG
        values[Key.debugMode] = false
        #endif
        return values
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: registeredDefaults)
    }
}
