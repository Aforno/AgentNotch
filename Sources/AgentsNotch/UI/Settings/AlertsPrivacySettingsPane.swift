import SwiftUI

struct AlertsPrivacySettingsPane: View {
    let runtime: AppRuntime
    let notificationsEnabled: Binding<Bool>
    let soundEnabled: Binding<Bool>
    let failureNotificationsEnabled: Binding<Bool>
    let answerFromNotchEnabled: Binding<Bool>
    let privacyModeEnabled: Binding<Bool>
    let retentionDays: Binding<Int>
    let notificationError: String?
    let requestClearHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "Alerts & Privacy",
                    detail: "Choose when Agents Notch interrupts you and what it retains."
                )
                AttentionSettingsSection(
                    notificationsEnabled: notificationsEnabled,
                    soundEnabled: soundEnabled,
                    failureNotificationsEnabled: failureNotificationsEnabled,
                    answerFromNotchEnabled: answerFromNotchEnabled
                )
                PrivacySettingsSection(privacyModeEnabled: privacyModeEnabled)
                HistorySettingsSection(
                    retentionDays: retentionDays,
                    hasCompletedSessions: !runtime.activity.recentSessions.isEmpty,
                    openActivityCenter: runtime.openActivityCenter,
                    openOnboarding: runtime.openOnboarding,
                    requestClearHistory: requestClearHistory
                )
                if let notificationError {
                    SettingsMessage(text: notificationError, symbol: "bell.slash.fill", color: .orange)
                }
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }
}
