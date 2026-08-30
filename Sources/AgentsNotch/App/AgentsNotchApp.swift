import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runtime = AppRuntime()
    private let instanceCoordinator = AppInstanceCoordinator(
        ownershipLock: FileInstanceOwnershipLock()
    )
    private var panelController: NotchPanelController?
    private var activityCenterWindowController: ActivityCenterWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var globalShortcutController: GlobalActivityShortcutController?
    private var recoveryStatusItem: SurfaceRecoveryStatusItem?
    private var handsOffLaunch = false
    private var monitorsActivity = false
    private var canPresentWindows = false
    private var pendingActivationRequest = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Listen before the handoff decision so a slightly later peer can still
        // wake this process. The dying process stops observing immediately.
        instanceCoordinator.startReceiving { [weak self] in
            self?.handleExistingInstanceActivation()
        }
        handsOffLaunch = instanceCoordinator.handOffIfNeeded()
        if handsOffLaunch {
            instanceCoordinator.stopReceiving()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !handsOffLaunch else {
            NSApp.terminate(nil)
            return
        }

        var defaults: [String: Any] = [
            "animationsEnabled": true,
            "displayPreference": DisplayPreference.primary.rawValue,
            "attentionNotificationsEnabled": false,
            "attentionNotificationSoundEnabled": false,
            "failureNotificationsEnabled": false,
            "historyRetentionDays": SessionHistoryPolicy.maximumCompletedSessionRetentionDays,
            "notchEnabled": true,
            "showVirtualNotch": false,
            "hasCompletedOnboarding": false,
            "automaticallyCheckForUpdates": true,
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
        monitorsActivity = true
        let panel = NotchPanelController(runtime: runtime)
        panelController = panel
        runtime.panelController = panel
        runtime.openActivityCenterHandler = { [weak self] in self?.showActivityCenter() }
        runtime.openOnboardingHandler = { [weak self] in self?.showOnboarding() }
        runtime.openSettingsHandler = { [weak self] pane in self?.showSettings(pane: pane) }
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
        panel.onSurfaceAvailabilityChanged = { [weak self] isAvailable in
            self?.recoveryStatusItem?.updateAvailability(isSurfaceAvailable: isAvailable)
        }

        Task { await runtime.start() }
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
        canPresentWindows = true
        if pendingActivationRequest {
            pendingActivationRequest = false
            showActivityCenter()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        instanceCoordinator.stopReceiving()
        guard monitorsActivity else { return }
        runtime.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(
            "Agent Notch monitors local agent activity"
        )
        monitorsActivity = false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showActivityCenter()
        return true
    }

    private func handleExistingInstanceActivation() {
        guard !handsOffLaunch else { return }
        guard canPresentWindows else {
            pendingActivationRequest = true
            return
        }
        showActivityCenter()
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

    private func showSettings(pane: SettingsPane? = nil) {
        let controller = settingsWindowController ?? SettingsWindowController(runtime: runtime)
        controller.onClose = { [weak self] in self?.settingsWindowController = nil }
        settingsWindowController = controller
        controller.show(pane: pane)
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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.runtime.updates.check()
                }
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
