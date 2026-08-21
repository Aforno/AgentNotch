import AppKit
import SwiftUI

@MainActor
final class ActivityCenterWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(runtime: AppRuntime) {
        let root = ActivityCenterView(runtime: runtime)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Activity Center"
        window.identifier = NSUserInterfaceItemIdentifier("activity-center")
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.contentView = NSHostingView(rootView: root)
        window.minSize = NSSize(width: 760, height: 500)
        let frameName = "AgentNotchActivityCenter"
        let restoredFrame = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        if !restoredFrame {
            window.center()
        }
        super.init(window: window)
        window.delegate = self
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

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
