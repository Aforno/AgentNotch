import SwiftUI

struct GeneralSettingsPane: View {
    let runtime: AppRuntime
    let launchAtLogin: Binding<Bool>
    let animationsEnabled: Binding<Bool>
    let notchEnabled: Binding<Bool>
    let showVirtualNotch: Binding<Bool>
    let automaticallyCheckForUpdates: Binding<Bool>
    let displayPreference: Binding<String>
    let globalActivityShortcut: Binding<String>
    let launchError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "General",
                    detail: "Control how Agent Notch starts and presents activity."
                )
                runtimeHealthMessages
                ApplicationSettingsSection(
                    launchAtLogin: launchAtLogin,
                    animationsEnabled: animationsEnabled,
                    notchEnabled: notchEnabled,
                    showVirtualNotch: showVirtualNotch,
                    automaticallyCheckForUpdates: automaticallyCheckForUpdates,
                    displayPreference: displayPreference,
                    globalActivityShortcut: globalActivityShortcut,
                    updates: runtime.updates
                )
                if let launchError {
                    SettingsMessage(text: launchError, symbol: "exclamationmark.triangle.fill", color: .red)
                }
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }

    @ViewBuilder
    private var runtimeHealthMessages: some View {
        if runtime.socketError != nil
            || runtime.persistenceError != nil
            || runtime.persistenceRecoveryNotice != nil
        {
            RuntimeHealthMessages(
                socketError: runtime.socketError,
                persistenceError: runtime.persistenceError,
                persistenceRecoveryNotice: runtime.persistenceRecoveryNotice
            )
        }
    }
}
