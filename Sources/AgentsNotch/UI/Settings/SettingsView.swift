import SwiftUI

struct SettingsView: View {
    let runtime: AppRuntime

    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @AppStorage("displayPreference") private var displayPreference = DisplayPreference.primary.rawValue
    @AppStorage("attentionNotificationsEnabled") private var attentionNotificationsEnabled = false
    @AppStorage("attentionNotificationSoundEnabled") private var attentionNotificationSoundEnabled = false
    @AppStorage("failureNotificationsEnabled") private var failureNotificationsEnabled = false
    @AppStorage("historyRetentionDays") private var historyRetentionDays = 30
    @AppStorage("notchEnabled") private var notchEnabled = true
    @AppStorage("showVirtualNotch") private var showVirtualNotch = false
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = false
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false
    @AppStorage("globalActivityShortcut") private var globalActivityShortcut = GlobalActivityShortcut.off.rawValue
    #if DEBUG
    @AppStorage("debugMode") private var debugMode = false
    #endif
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchError: String?
    @State private var notificationError: String?
    @State private var confirmsClearHistory = false
    @State private var pane = SettingsPane.general

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneSelector(selection: $pane)
            NotchHairline()
            selectedPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(NotchWindowPalette.primaryText)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 480, idealHeight: 560)
        .deepBlackWindowSurface()
        .onAppear { launchAtLogin = LaunchAtLoginService.isEnabled }
        .onChange(of: historyRetentionDays) { _, days in runtime.applyHistoryRetention(days: days) }
        .onChange(of: automaticallyCheckForUpdates) { _, enabled in
            if enabled { runtime.updates.checkAutomaticallyIfNeeded() }
        }
        .onChange(of: displayPreference) { _, _ in runtime.refreshNotchSurface() }
        .onChange(of: notchEnabled) { _, _ in runtime.refreshNotchSurface() }
        .onChange(of: showVirtualNotch) { _, _ in runtime.refreshNotchSurface() }
        .onChange(of: globalActivityShortcut) { _, value in runtime.updateGlobalShortcut(value) }
        .confirmationDialog("Clear completed session history?", isPresented: $confirmsClearHistory) {
            Button("Clear History", role: .destructive) { runtime.clearHistory() }
        } message: {
            Text("Active and waiting sessions will be kept.")
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch pane {
        case .general:
            GeneralSettingsPane(
                runtime: runtime,
                launchAtLogin: launchBinding,
                animationsEnabled: $animationsEnabled,
                notchEnabled: $notchEnabled,
                showVirtualNotch: $showVirtualNotch,
                automaticallyCheckForUpdates: $automaticallyCheckForUpdates,
                displayPreference: $displayPreference,
                globalActivityShortcut: $globalActivityShortcut,
                launchError: launchError
            )
        case .alertsPrivacy:
            AlertsPrivacySettingsPane(
                runtime: runtime,
                notificationsEnabled: notificationBinding,
                soundEnabled: $attentionNotificationSoundEnabled,
                failureNotificationsEnabled: $failureNotificationsEnabled,
                privacyModeEnabled: $privacyModeEnabled,
                retentionDays: $historyRetentionDays,
                notificationError: notificationError,
                requestClearHistory: { confirmsClearHistory = true }
            )
        case .integrations:
            IntegrationSettingsPane(runtime: runtime)
        #if DEBUG
        case .debug:
            DebugSettingsPane(runtime: runtime, debugMode: debugModeBinding)
        #endif
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { value in
                do {
                    try LaunchAtLoginService.setEnabled(value)
                    launchAtLogin = LaunchAtLoginService.isEnabled
                    launchError = nil
                } catch {
                    launchAtLogin = LaunchAtLoginService.isEnabled
                    launchError = error.localizedDescription
                }
            }
        )
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { attentionNotificationsEnabled },
            set: { enabled in
                if !enabled {
                    attentionNotificationsEnabled = false
                    notificationError = nil
                    return
                }
                Task { @MainActor in
                    let granted = await runtime.notifications.setEnabled(true)
                    attentionNotificationsEnabled = granted
                    notificationError = granted
                        ? nil
                        : "Notifications are disabled in System Settings. The notch will still show attention states."
                }
            }
        )
    }

    #if DEBUG
    private var debugModeBinding: Binding<Bool> {
        Binding(
            get: { debugMode },
            set: { enabled in
                debugMode = enabled
                if !enabled { runtime.simulator.reset() }
            }
        )
    }
    #endif
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case alertsPrivacy
    case integrations
    #if DEBUG
    case debug
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .alertsPrivacy: "Alerts & Privacy"
        case .integrations: "Integrations"
        #if DEBUG
        case .debug: "Debug"
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .alertsPrivacy: "bell.badge"
        case .integrations: "point.3.connected.trianglepath.dotted"
        #if DEBUG
        case .debug: "hammer"
        #endif
        }
    }
}

private struct SettingsPaneSelector: View {
    @Binding var selection: SettingsPane

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsPane.allCases) { candidate in
                Button {
                    selection = candidate
                } label: {
                    Label(candidate.title, systemImage: candidate.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(selection == candidate ? 0.92 : 0.5))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            selection == candidate ? NotchWindowPalette.raisedStrong : .clear,
                            in: RoundedRectangle(cornerRadius: NotchWindowMetrics.controlRadius, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == candidate ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, NotchWindowMetrics.contentInset)
        .padding(.vertical, 10)
        .background(NotchWindowPalette.background)
    }
}
