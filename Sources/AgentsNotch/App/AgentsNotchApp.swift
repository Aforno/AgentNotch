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
        ]
        #if DEBUG
        defaults["debugMode"] = false
        #endif
        UserDefaults.standard.register(defaults: defaults)

        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Agents Notch monitors local agent activity"
        )
        let panel = NotchPanelController(runtime: runtime)
        panelController = panel
        runtime.panelController = panel
        let activityCenter = ActivityCenterWindowController(runtime: runtime)
        activityCenterWindowController = activityCenter
        let onboarding = OnboardingWindowController(runtime: runtime)
        onboardingWindowController = onboarding
        let settings = SettingsWindowController(runtime: runtime)
        settingsWindowController = settings
        runtime.openActivityCenterHandler = { [weak activityCenter] in activityCenter?.show() }
        runtime.openOnboardingHandler = { [weak onboarding] in onboarding?.show() }
        runtime.openSettingsHandler = { [weak settings] in settings?.show() }
        panel.show()

        Task { await runtime.start() }
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            onboarding.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(
            "Agents Notch monitors local agent activity"
        )
    }
}

@main
struct AgentsNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            AgentMenuBarView(runtime: appDelegate.runtime)
        } label: {
            MenuBarNotchIcon(
                activeCount: appDelegate.runtime.activity.activeSessions.count,
                attentionCount: appDelegate.runtime.activity.attentionCount
            )
        }
        .commands {
            // Settings is a dedicated NSWindowController (same chrome as Activity
            // Center) rather than a SwiftUI Settings scene, so minimize/zoom/resize
            // traffic lights stay enabled and the title bar stays pure black.
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

                Button("Show Setup") {
                    appDelegate.runtime.openOnboarding()
                }
            }
        }
    }

}
