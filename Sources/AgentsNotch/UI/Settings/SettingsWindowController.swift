import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(runtime: AppRuntime) {
        let root = SettingsView(runtime: runtime)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.contentView = NSHostingView(rootView: root)
        window.minSize = NSSize(width: 520, height: 480)
        let frameName = "AgentsNotchSettings"
        let restoredFrame = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        if !restoredFrame {
            window.center()
        }
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
