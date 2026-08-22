import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runtime = AppRuntime()
    private var panelController: NotchPanelController?
    private var activityCenterWindowController: ActivityCenterWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var globalShortcutController: GlobalActivityShortcutController?
    private var recoveryStatusItem: SurfaceRecoveryStatusItem?
    private nonisolated(unsafe) var preferenceObserver: NSObjectProtocol?
    private nonisolated(unsafe) var screenChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var defaults: [String: Any] = [
            "animationsEnabled": true,
            "displayPreference": DisplayPreference.primary.rawValue,
            "attentionNotificationsEnabled": false,
            "attentionNotificationSoundEnabled": false,
            "failureNotificationsEnabled": false,
            "historyRetentionDays": 30,
            "notchEnabled": true,
            "showVirtualNotch": false,
            "hasCompletedOnboarding": false,
            "automaticallyCheckForUpdates": false,
            "privacyModeEnabled": false,
            "answerFromNotchEnabled": false,
            "globalActivityShortcut": GlobalActivityShortcut.off.rawValue,
        ]
        #if DEBUG
        defaults["debugMode"] = false
        #endif
        UserDefaults.standard.register(defaults: defaults)

        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Agent Notch monitors local agent activity"
        )
        let panel = NotchPanelController(runtime: runtime)
        panelController = panel
        runtime.panelController = panel
        runtime.openActivityCenterHandler = { [weak self] in self?.showActivityCenter() }
        runtime.openOnboardingHandler = { [weak self] in self?.showOnboarding() }
        runtime.openSettingsHandler = { [weak self] in self?.showSettings() }
        let shortcutController = GlobalActivityShortcutController { [weak self] in
            self?.runtime.openActivityCenter()
        }
        globalShortcutController = shortcutController
        runtime.updateGlobalShortcutHandler = { [weak shortcutController] rawValue in
            shortcutController?.configure(rawValue: rawValue)
        }
        shortcutController.configure(
            rawValue: UserDefaults.standard.string(forKey: "globalActivityShortcut")
                ?? GlobalActivityShortcut.off.rawValue
        )
        panel.show()

        // The notch surface is the only built-in affordance for reaching this
        // accessory app. When it is unavailable (notch disabled, non-notch Mac),
        // keep a menu bar item alive as the recovery entry point.
        recoveryStatusItem = SurfaceRecoveryStatusItem(runtime: runtime)
        refreshRecoveryStatusItem()
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRecoveryStatusItem() }
        }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRecoveryStatusItem() }
        }

        Task { await runtime.start() }
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        runtime.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(
            "Agent Notch monitors local agent activity"
        )
    }

    private func refreshRecoveryStatusItem() {
        let surfaceAvailable = panelController?.isSurfaceEnabled ?? true
        recoveryStatusItem?.updateAvailability(isSurfaceAvailable: surfaceAvailable)
    }

    private func showActivityCenter() {
        let controller = activityCenterWindowController ?? ActivityCenterWindowController(runtime: runtime)
        controller.onClose = { [weak self] in self?.activityCenterWindowController = nil }
        activityCenterWindowController = controller
        controller.show()
    }

    private func showOnboarding() {
        let controller = onboardingWindowController ?? OnboardingWindowController(runtime: runtime)
        controller.onClose = { [weak self] in self?.onboardingWindowController = nil }
        onboardingWindowController = controller
        controller.show()
    }

    private func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController(runtime: runtime)
        controller.onClose = { [weak self] in self?.settingsWindowController = nil }
        settingsWindowController = controller
        controller.show()
    }
}

@main
struct AgentsNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Host for app commands only. The visible Settings window is
        // SettingsWindowController so the title bar stays the same chrome
        // as Activity Center.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.runtime.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandMenu("Agents") {
                Button("Open Activity Center") {
                    appDelegate.runtime.openActivityCenter()
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Find Sessions…") {
                    appDelegate.runtime.focusActivitySearch()
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Show Setup") {
                    appDelegate.runtime.openOnboarding()
                }
            }
        }
    }

}
