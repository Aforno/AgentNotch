import AppKit
import SwiftUI

@MainActor
final class ActivityCenterWindowController: NSWindowController {
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
        window.contentView = NSHostingView(rootView: root)
        window.minSize = NSSize(width: 720, height: 480)
        let frameName = "AgentsNotchActivityCenter"
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
