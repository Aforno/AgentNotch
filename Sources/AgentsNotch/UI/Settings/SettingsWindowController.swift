import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let presentation = SettingsPresentation()

    init(runtime: AppRuntime) {
        let root = SettingsView(runtime: runtime, presentation: presentation)
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
        let frameName = "AgentNotchSettings"
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

    func show(pane: SettingsPane? = nil) {
        if let pane {
            presentation.pane = pane
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
