import AppKit

/// Collapses a pinned notch thread when the user clicks outside the panel.
///
/// Detail presentation is hover-independent so a selected thread stays readable
/// after the pointer leaves. Clicks outside the notch are the matching exit,
/// including clicks in other apps and in this app's other windows.
@MainActor
final class NotchOutsideClickMonitor {
    private let notchFrame: () -> CGRect?
    private nonisolated(unsafe) var globalMonitor: Any?
    private nonisolated(unsafe) var localMonitor: Any?
    private var onDismiss: (() -> Void)?

    var isActive: Bool { globalMonitor != nil || localMonitor != nil }

    init(notchFrame: @escaping () -> CGRect? = {
        NSApp.windows.compactMap { $0 as? NotchPanel }.first?.frame
    }) {
        self.notchFrame = notchFrame
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    static func shouldDismiss(clickAt location: CGPoint, notchFrame: CGRect?) -> Bool {
        guard let notchFrame else { return false }
        return !notchFrame.contains(location)
    }

    func start(onDismiss: @escaping () -> Void) {
        stop()
        self.onDismiss = onDismiss

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            // AppKit delivers global and local monitor handlers on the main thread.
            MainActor.assumeIsolated { self?.considerClick() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.considerClick() }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onDismiss = nil
    }

    private func considerClick() {
        guard Self.shouldDismiss(clickAt: NSEvent.mouseLocation, notchFrame: notchFrame()) else {
            return
        }
        let callback = onDismiss
        // Defer so the view can tear the monitor down outside this handler.
        DispatchQueue.main.async {
            callback?()
        }
    }
}
