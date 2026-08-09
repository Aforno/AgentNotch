import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runtime = AppRuntime()
    private var panelController: NotchPanelController?
    private var activityCenterWindowController: ActivityCenterWindowController?
    private var onboardingWindowController: OnboardingWindowController?

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
        runtime.openActivityCenterHandler = { [weak activityCenter] in activityCenter?.show() }
        runtime.openOnboardingHandler = { [weak onboarding] in onboarding?.show() }
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
        MenuBarExtra("Agents Notch", systemImage: menuBarSymbol) {
            AgentMenuBarView(runtime: appDelegate.runtime)
        }

        Settings {
            SettingsView(runtime: appDelegate.runtime)
        }
        .commands {
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

    private var menuBarSymbol: String {
        if appDelegate.runtime.activity.attentionCount > 0 {
            return "exclamationmark.bubble.fill"
        }
        if !appDelegate.runtime.activity.activeSessions.isEmpty {
            return "bolt.horizontal.circle.fill"
        }
        return "bolt.horizontal.circle"
    }
}
