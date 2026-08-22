import AppKit

/// Menu bar fallback for reaching the app when the notch surface is hidden.
/// The app is accessory-only with no dock icon; without this, disabling the
/// notch on a non-notch Mac leaves no way back into Settings.
@MainActor
final class SurfaceRecoveryStatusItem {
    private var statusItem: NSStatusItem?
    private let runtime: AppRuntime

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    var isVisible: Bool { statusItem != nil }

    func updateAvailability(isSurfaceAvailable: Bool) {
        if isSurfaceAvailable {
            guard let statusItem else { return }
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if statusItem == nil {
            install()
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.badge.minus", accessibilityDescription: "Agent Notch")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let activity = NSMenuItem(
            title: "Open Activity Center",
            action: #selector(openActivityCenter),
            keyEquivalent: "1"
        )
        activity.keyEquivalentModifierMask = [.command]
        activity.target = self
        menu.addItem(activity)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let setup = NSMenuItem(
            title: "Show Setup",
            action: #selector(showSetup),
            keyEquivalent: ""
        )
        setup.target = self
        menu.addItem(setup)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit Agent Notch",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func openActivityCenter() {
        runtime.openActivityCenter()
    }

    @objc private func openSettings() {
        runtime.openSettings()
    }

    @objc private func showSetup() {
        runtime.openOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
