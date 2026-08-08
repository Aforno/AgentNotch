import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let runtime = AppRuntime()
    private var panelController: NotchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var defaults: [String: Any] = [
            "animationsEnabled": true,
            "displayPreference": DisplayPreference.primary.rawValue,
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
        panel.show()

        Task { await runtime.start() }
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
        Settings {
            SettingsView(runtime: appDelegate.runtime)
        }
    }
}
