@testable import AgentsNotch
import XCTest

final class AppPreferencesTests: XCTestCase {
    func testRegisteredDefaultsMatchInitialSettings() {
        let defaults = AppPreferences.registeredDefaults

        XCTAssertEqual(defaults[AppPreferences.Key.animationsEnabled] as? Bool, true)
        XCTAssertEqual(defaults[AppPreferences.Key.automaticallyCheckForUpdates] as? Bool, true)
        XCTAssertEqual(defaults[AppPreferences.Key.notchEnabled] as? Bool, true)
        XCTAssertEqual(
            defaults[AppPreferences.Key.displayPreference] as? String,
            DisplayPreference.primary.rawValue
        )
        XCTAssertEqual(
            defaults[AppPreferences.Key.globalActivityShortcut] as? String,
            GlobalActivityShortcut.off.rawValue
        )
        XCTAssertEqual(
            defaults[AppPreferences.Key.historyRetentionDays] as? Int,
            SessionHistoryPolicy.maximumCompletedSessionRetentionDays
        )
        XCTAssertEqual(defaults[AppPreferences.Key.answerFromNotchEnabled] as? Bool, false)
        XCTAssertEqual(defaults[AppPreferences.Key.attentionNotificationsEnabled] as? Bool, false)
        XCTAssertEqual(defaults[AppPreferences.Key.failureNotificationsEnabled] as? Bool, false)
        XCTAssertEqual(defaults[AppPreferences.Key.hasCompletedOnboarding] as? Bool, false)
        XCTAssertEqual(defaults[AppPreferences.Key.privacyModeEnabled] as? Bool, false)
        XCTAssertEqual(defaults[AppPreferences.Key.showVirtualNotch] as? Bool, false)
    }
}
