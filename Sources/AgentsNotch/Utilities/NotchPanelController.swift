import AppKit
import SwiftUI

@MainActor
final class NotchPanelController: NSWindowController {
    private let runtime: AppRuntime
    private var geometry: DisplayGeometry
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?
    private nonisolated(unsafe) var globalPointerObserver: Any?
    private nonisolated(unsafe) var localPointerObserver: Any?
    private lazy var frameScheduler = NotchPanelFrameScheduler { [weak self] size, animated in
        self?.reposition(width: size.width, height: size.height, animated: animated)
    }

    init(runtime: AppRuntime) {
        self.runtime = runtime
        // NSScreen.screens can be empty during clamshell boot; never force-index.
        let screen = DisplayResolver.preferredScreen()
        geometry = screen.map { DisplayGeometry.detect(on: $0) } ?? .fallback

        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        super.init(window: panel)
        configure(panel)
        installContent(in: panel)
        observeDisplayChanges()
        updatePointerDisplayObservation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let globalPointerObserver { NSEvent.removeMonitor(globalPointerObserver) }
        if let localPointerObserver { NSEvent.removeMonitor(localPointerObserver) }
    }

    var isSurfaceEnabled: Bool {
        UserDefaults.standard.bool(forKey: "notchEnabled")
            && (geometry.hasPhysicalNotch || UserDefaults.standard.bool(forKey: "showVirtualNotch"))
    }

    /// Makes the notch panel visible.
    ///
    /// - Parameter resetToCompact: When true, snap the AppKit frame to compact
    ///   notch dimensions (display changes, first presentation). When false and
    ///   the panel is already visible, only order front — leave size to
    ///   NotchRootView so presentSession / detail re-entry cannot clip expanded
    ///   content back to compact while SwiftUI layout stays on `.detail`.
    func show(resetToCompact: Bool = false) {
        guard isSurfaceEnabled else {
            window?.orderOut(nil)
            return
        }
        if resetToCompact || window?.isVisible != true {
            let snapshot = runtime.activity.notchSnapshot
            let hasActiveAgents = !snapshot.activeSessions.isEmpty
            let compactEarWidth = DynamicIslandSpacing.compactEarWidth(
                for: snapshot.activeGroupCount
            )
            reposition(
                width: geometry.notchWidth + (hasActiveAgents ? compactEarWidth * 2 : 0),
                height: geometry.notchHeight + (hasActiveAgents ? 2 : 0)
            )
        }
        window?.orderFrontRegardless()
    }

    /// Applies the three preferences that affect panel visibility or display
    /// placement. If the current display is unchanged, keep the AppKit frame
    /// owned by NotchRootView so an expanded list/detail is never clipped back
    /// to compact dimensions by an unrelated preference write.
    func refreshPreferences() {
        updatePointerDisplayObservation()
        guard let screen = DisplayResolver.preferredScreen() else { return }
        let updated = DisplayGeometry.detect(on: screen)
        let geometryChanged = updated != geometry
        if geometryChanged {
            geometry = updated
            if let panel = window as? NSPanel { installContent(in: panel) }
        }
        guard isSurfaceEnabled else {
            window?.orderOut(nil)
            return
        }
        if geometryChanged {
            show(resetToCompact: true)
        } else if window?.isVisible != true {
            show(resetToCompact: true)
        }
    }

    func updateSize(_ size: CGSize, animated: Bool) {
        frameScheduler.schedule(size: size, animated: animated)
    }

    private func configure(_ panel: NSPanel) {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
    }

    private func installContent(in panel: NSPanel) {
        let rootView = NotchRootView(
            runtime: runtime,
            geometry: geometry,
            onSizeChange: { [weak self] size, animated in
                self?.updateSize(size, animated: animated)
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        // Don't size the window from SwiftUI intrinsic content — the panel
        // frame is the single source of truth for bounds during animation.
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        panel.contentView = hostingView
    }

    private func observeDisplayChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplay() }
        }
    }

    private func updatePointerDisplayObservation() {
        let followsPointer = UserDefaults.standard.string(forKey: "displayPreference")
            == DisplayPreference.pointer.rawValue

        guard followsPointer else {
            removePointerDisplayObservation()
            return
        }

        if globalPointerObserver == nil {
            globalPointerObserver = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] _ in
                // AppKit delivers global and local monitor handlers on the main thread.
                MainActor.assumeIsolated { self?.refreshPointerDisplayIfNeeded() }
            }
        }
        if localPointerObserver == nil {
            localPointerObserver = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
            ) { [weak self] event in
                MainActor.assumeIsolated { self?.refreshPointerDisplayIfNeeded() }
                return event
            }
        }
    }

    private func removePointerDisplayObservation() {
        if let globalPointerObserver {
            NSEvent.removeMonitor(globalPointerObserver)
            self.globalPointerObserver = nil
        }
        if let localPointerObserver {
            NSEvent.removeMonitor(localPointerObserver)
            self.localPointerObserver = nil
        }
    }

    private func refreshPointerDisplayIfNeeded() {
        let pointerLocation = NSEvent.mouseLocation
        guard !geometry.screenFrame.contains(pointerLocation),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointerLocation) }),
              screen.frame != geometry.screenFrame else { return }
        refreshDisplay(force: true)
    }

    private func refreshDisplay(force: Bool = false) {
        guard let screen = DisplayResolver.preferredScreen() else { return }
        let updated = DisplayGeometry.detect(on: screen)
        let geometryChanged = updated != geometry
        guard force || geometryChanged else { return }
        if geometryChanged {
            geometry = updated
            if let panel = window as? NSPanel { installContent(in: panel) }
        }
        show(resetToCompact: true)
    }

    private func reposition(width: CGFloat, height: CGFloat, animated: Bool = false) {
        guard let panel = window else { return }

        let size = CGSize(width: width.rounded(.up), height: height.rounded(.up))
        let targetFrame = frame(for: size)

        // Skip no-op updates (SwiftUI may re-report the same settled size).
        let current = panel.frame
        if abs(current.width - targetFrame.width) < 0.5,
           abs(current.height - targetFrame.height) < 0.5,
           abs(current.midX - targetFrame.midX) < 0.5,
           abs(current.maxY - targetFrame.maxY) < 0.5 {
            return
        }

        // Visual width/height morph lives in SwiftUI. AppKit only snaps the
        // panel to the container size (union during animation, final after).
        // Using animator().setFrame here was unreliable for height on top-edge
        // panels and fought the SwiftUI animation.
        _ = animated
        // `display: true` can synchronously re-enter NSHostingView's constraint
        // pass. The layer-backed hosting view redraws on its normal display
        // cycle, so a deferred, non-forcing frame change is sufficient.
        panel.setFrame(targetFrame, display: false)
    }

    private func frame(for size: CGSize, screenTop: CGFloat? = nil) -> CGRect {
        let top = screenTop ?? geometry.screenFrame.maxY
        let height = size.height
        return CGRect(
            x: geometry.centerX - size.width / 2,
            y: top - height,
            width: size.width,
            height: height
        )
    }

}
