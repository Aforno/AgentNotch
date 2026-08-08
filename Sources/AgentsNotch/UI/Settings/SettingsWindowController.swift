import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(runtime: AppRuntime) {
        let hostingController = NSHostingController(
            rootView: SettingsView(runtime: runtime)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 680, height: 500)
        window.setContentSize(NSSize(width: 720, height: 540))
        window.center()
        window.setFrameAutosaveName("AgentsNotchSettings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
