import AgentsNotchCore
import AppKit
import SwiftUI

/// Compact dark pill with hairline border — Settings, Setup, and other deep-black windows.
struct NotchPillButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchWindowFont.control)
            .foregroundStyle(
                destructive
                    ? Color.red.opacity(configuration.isPressed ? 0.7 : 0.88)
                    : Color.white.opacity(configuration.isPressed ? 0.62 : 0.82)
            )
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                configuration.isPressed
                    ? NotchWindowPalette.raisedPressed
                    : NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Square icon control matching `NotchPillButtonStyle` (refresh, etc.).
struct NotchIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.55 : 0.72))
            .frame(width: 26, height: 26)
            .background(
                configuration.isPressed
                    ? NotchWindowPalette.raisedPressed
                    : NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Quiet, borderless control that matches the notch's primary action button
/// (`AgentDetailView`): 11pt semibold on a soft white fill, radius 8.
struct ActivityActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchWindowFont.control.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                configuration.isPressed
                    ? NotchWindowPalette.raisedPressed
                    : NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: NotchWindowMetrics.controlRadius, style: .continuous)
            )
    }
}

/// Section label used across Activity Center and Settings: sentence case,
/// semibold, muted — no uppercase, no monospace, no `.black` weight.
struct NotchSectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(NotchWindowFont.sectionLabel)
                .foregroundStyle(.white.opacity(0.74))
            if let trailing {
                Text(trailing)
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}

/// T3-style dropdown: dark pill trigger + solid floating menu below it (no arrow, no speech bubble).
/// Uses a borderless `NSPanel` so the menu is fully opaque and sits above all sibling content.
struct NotchMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    @State private var anchorView: NSView?
    @State private var isExpanded = false
    @State private var panel = NotchDropdownPanel()

    private static var triggerBackground: Color { Color(red: 0.16, green: 0.16, blue: 0.17) }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }

    var body: some View {
        Button {
            toggleMenu()
        } label: {
            HStack(spacing: 7) {
                Text(selectedTitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Self.triggerBackground,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .background(
            NotchViewAnchor { view in
                anchorView = view
            }
        )
        .onDisappear {
            panel.dismiss()
            isExpanded = false
        }
    }

    private func toggleMenu() {
        if panel.isPresented || isExpanded {
            panel.dismiss()
            isExpanded = false
            return
        }
        guard let anchorView else { return }

        let titles = options.map(\.title)
        let values = options.map(\.value)
        let selectedIndex = values.firstIndex(of: selection) ?? 0

        panel.present(
            relativeTo: anchorView,
            titles: titles,
            selectedIndex: selectedIndex,
            onSelect: { index in
                if values.indices.contains(index) {
                    selection = values[index]
                }
                isExpanded = false
            },
            onDismiss: {
                isExpanded = false
            }
        )
        isExpanded = true
    }
}

// MARK: - AppKit floating dropdown

/// Captures the underlying `NSView` for window-coordinate positioning.
/// Sized to the control via `.background` so `bounds` match the trigger pill.
private struct NotchViewAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Invisible but laid out at the control’s size (do not hide — zero frames break positioning).
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView) }
    }
}

/// Borderless opaque panel positioned under a control — matches T3's flat menu, not a popover balloon.
/// Dismisses on outside click, scroll, or window move/resize so it never floats detached from its control.
@MainActor
final class NotchDropdownPanel {
    private var panel: NSPanel?
    private weak var anchor: NSView?
    private var eventMonitor: Any?
    private var scrollObservation: NSObjectProtocol?
    private var windowObservations: [NSObjectProtocol] = []
    private var onDismiss: (() -> Void)?

    private static let menuFill = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)

    var isPresented: Bool { panel != nil }

    func present(
        relativeTo anchor: NSView,
        titles: [String],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss(notify: false)
        self.anchor = anchor
        self.onDismiss = onDismiss

        let content = NotchDropdownMenuContent(
            titles: titles,
            selectedIndex: selectedIndex,
            onSelect: { [weak self] index in
                onSelect(index)
                self?.dismiss()
            }
        )

        let hosting = NSHostingView(rootView: content)
        // Force a layout pass so fittingSize is non-zero.
        let fitting = hosting.fittingSize
        let size = NSSize(
            width: max(168, max(fitting.width, anchor.bounds.width + 24)),
            height: max(fitting.height, 36)
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = Self.menuFill.cgColor
        hosting.layer?.cornerRadius = 10
        hosting.layer?.masksToBounds = true

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = hosting

        if let window = anchor.window {
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            // Screen coords: y grows up. Place the panel just below the trigger.
            let origin = NSPoint(
                x: max(anchorOnScreen.minX, anchorOnScreen.maxX - size.width),
                y: anchorOnScreen.minY - size.height - 4
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        panel.orderFront(nil)
        self.panel = panel
        installDismissObservers(anchor: anchor)
    }

    func dismiss() {
        dismiss(notify: true)
    }

    private func installDismissObservers(anchor: NSView) {
        // Outside click, and any scroll gesture — menus should not stick while the page moves.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            guard let self, self.panel != nil else { return event }

            if event.type == .scrollWheel {
                // Ignore tiny momentum noise; still close on intentional scroll.
                if abs(event.scrollingDeltaY) > 0.5 || abs(event.scrollingDeltaX) > 0.5 {
                    self.dismiss()
                }
                return event
            }

            guard let panel = self.panel else { return event }
            let mouse = NSEvent.mouseLocation

            // Clicks inside the menu stay on the menu.
            if panel.frame.contains(mouse) {
                return event
            }

            // Clicks on the trigger: let the button close the menu (avoid dismiss+reopen).
            if let anchor = self.anchor, let window = anchor.window {
                let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
                let anchorOnScreen = window.convertToScreen(anchorInWindow)
                if anchorOnScreen.insetBy(dx: -4, dy: -4).contains(mouse) {
                    return event
                }
            }

            self.dismiss()
            return event
        }

        // SwiftUI / AppKit scroll views also move their clip view bounds without a scrollWheel event
        // in some paths — dismiss when the enclosing scroll content moves.
        if let scrollView = anchor.enclosingScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObservation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.dismiss()
                }
            }
        }

        if let window = anchor.window {
            let center = NotificationCenter.default
            for name in [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.willCloseNotification,
            ] {
                windowObservations.append(
                    center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        Task { @MainActor in
                            self?.dismiss()
                        }
                    }
                )
            }
        }
    }

    private func dismiss(notify: Bool) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let scrollObservation {
            NotificationCenter.default.removeObserver(scrollObservation)
            self.scrollObservation = nil
        }
        for observation in windowObservations {
            NotificationCenter.default.removeObserver(observation)
        }
        windowObservations.removeAll()

        panel?.orderOut(nil)
        panel = nil
        anchor = nil
        guard notify else {
            onDismiss = nil
            return
        }
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

private struct NotchDropdownMenuContent: View {
    let titles: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    private static let menuFill = Color(red: 0.13, green: 0.13, blue: 0.14)
    private static let selectedFill = Color(red: 0.24, green: 0.24, blue: 0.26)

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                Button {
                    onSelect(index)
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            index == selectedIndex ? Self.selectedFill : Self.menuFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Self.menuFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}
