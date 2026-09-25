import AppKit
import Observation
import SwiftUI

struct NotchMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    let accessibilityLabel: String

    @State private var anchorView: NSView?
    @State private var isExpanded = false
    @State private var panel = NotchDropdownPanel()

    private var selectedTitle: String { options.first(where: { $0.value == selection })?.title ?? "" }

    var body: some View {
        Button(action: toggleMenu) {
            HStack(spacing: 7) {
                Text(selectedTitle)
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(NotchWindowFont.glyph)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 28, maxHeight: 28, alignment: .leading)
        }
        .buttonStyle(NotchMenuTriggerStyle(isExpanded: isExpanded))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedTitle)
        .accessibilityHint("Press Return, then use the arrow keys to choose an option")
        .background(NotchViewAnchor { anchorView = $0 })
        .onDisappear { panel.dismiss(); isExpanded = false }
    }

    private func toggleMenu() {
        if panel.isPresented || isExpanded {
            panel.dismiss(); isExpanded = false; return
        }
        guard let anchorView else { return }
        let titles = options.map(\.title)
        let values = options.map(\.value)
        panel.present(
            relativeTo: anchorView,
            titles: titles,
            selectedIndex: values.firstIndex(of: selection) ?? 0,
            onSelect: { index in
                if values.indices.contains(index) { selection = values[index] }
                isExpanded = false
            },
            onDismiss: { isExpanded = false }
        )
        isExpanded = true
    }
}

/// The picker trigger is a control on a deep-black window, so it shares the
/// pill vocabulary. An open menu holds the hover fill so the pair reads as one.
private struct NotchMenuTriggerStyle: ButtonStyle {
    let isExpanded: Bool

    func makeBody(configuration: Configuration) -> some View {
        NotchHoverSurface(
            isPressed: configuration.isPressed,
            rest: isExpanded ? NotchControlFill.hover : NotchControlFill.rest,
            hover: NotchControlFill.hover,
            pressed: NotchControlFill.pressed
        ) { fill in
            configuration.label.notchControlSurface(fill: fill)
        }
    }
}

private struct NotchViewAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); view.wantsLayer = true
        DispatchQueue.main.async { onResolve(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { DispatchQueue.main.async { onResolve(nsView) } }
}

@Observable
@MainActor
final class NotchDropdownMenuModel {
    let titles: [String]
    private(set) var highlightedIndex: Int
    private let onSelect: (Int) -> Void

    init(titles: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.titles = titles
        highlightedIndex = min(max(selectedIndex, 0), max(0, titles.count - 1))
        self.onSelect = onSelect
    }

    func move(by offset: Int) {
        guard !titles.isEmpty else { return }
        highlightedIndex = min(max(highlightedIndex + offset, 0), titles.count - 1)
    }

    /// Pointer and keyboard drive the same highlight, so the menu tracks
    /// whichever the user reached for last.
    func highlight(_ index: Int) {
        guard titles.indices.contains(index) else { return }
        highlightedIndex = index
    }
    func select(_ index: Int) { guard titles.indices.contains(index) else { return }; onSelect(index) }
    func selectHighlighted() { select(highlightedIndex) }
}

@MainActor
final class NotchDropdownPanel {
    private var panel: NSPanel?
    private var model: NotchDropdownMenuModel?
    private weak var anchor: NSView?
    private var eventMonitor: Any?
    private var scrollObservation: NSObjectProtocol?
    private var lifecycleObservations: [NSObjectProtocol] = []
    private var onDismiss: (() -> Void)?
    /// Mirrors `NotchWindowPalette.floating` for the panel's backing layer.
    private static let menuFill = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
    var isPresented: Bool { panel != nil }

    func present(relativeTo anchor: NSView, titles: [String], selectedIndex: Int, onSelect: @escaping (Int) -> Void, onDismiss: @escaping () -> Void) {
        dismiss(notify: false)
        self.anchor = anchor
        self.onDismiss = onDismiss
        let model = NotchDropdownMenuModel(titles: titles, selectedIndex: selectedIndex) { [weak self] index in
            onSelect(index); self?.dismiss()
        }
        self.model = model
        let hosting = NSHostingView(rootView: NotchDropdownMenuContent(model: model))
        let fitting = hosting.fittingSize
        let size = NSSize(width: max(168, max(fitting.width, anchor.bounds.width + 24)), height: max(fitting.height, 36))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = Self.menuFill.cgColor
        hosting.layer?.cornerRadius = 10
        hosting.layer?.masksToBounds = true

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = true
        panel.contentView = hosting
        panel.setAccessibilityLabel("Options")
        if let window = anchor.window {
            let anchorOnScreen = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let screen = window.screen
                ?? NSScreen.screens.first { $0.frame.intersects(anchorOnScreen) }
                ?? NSScreen.main
            panel.setFrameOrigin(Self.menuOrigin(
                size: size,
                anchor: anchorOnScreen,
                screen: screen?.visibleFrame
            ))
        }
        panel.orderFront(nil)
        self.panel = panel
        installObservers(anchor: anchor)
    }

    func dismiss() { dismiss(notify: true) }

    /// Drops the menu below the anchor, flips it above when the space below is
    /// too short, then clamps to the visible frame so no edge runs off screen.
    static func menuOrigin(size: NSSize, anchor: NSRect, screen: NSRect?) -> NSPoint {
        let gap: CGFloat = 4
        let trailingAligned = max(anchor.minX, anchor.maxX - size.width)
        let below = anchor.minY - size.height - gap
        guard let screen else { return NSPoint(x: trailingAligned, y: below) }

        var y = below
        if y < screen.minY {
            let above = anchor.maxY + gap
            y = above + size.height <= screen.maxY ? above : screen.minY
        }
        let maximumX = max(screen.minX, screen.maxX - size.width)
        return NSPoint(x: min(max(trailingAligned, screen.minX), maximumX), y: y)
    }

    @discardableResult
    func handleKeyCode(_ keyCode: UInt16) -> Bool {
        guard isPresented, let model else { return false }
        switch keyCode {
        case 125: model.move(by: 1)
        case 126: model.move(by: -1)
        case 36, 76: model.selectHighlighted()
        case 53: dismiss()
        default: return false
        }
        return true
    }

    private func installObservers(anchor: NSView) {
        let center = NotificationCenter.default
        lifecycleObservations.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type == .keyDown { return self.handleKeyCode(event.keyCode) ? nil : event }
            if event.type == .scrollWheel {
                if abs(event.scrollingDeltaY) > 0.5 || abs(event.scrollingDeltaX) > 0.5 { self.dismiss() }
                return event
            }
            let mouse = NSEvent.mouseLocation
            if panel.frame.contains(mouse) { return event }
            if let anchor = self.anchor, let window = anchor.window {
                let frame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                if frame.insetBy(dx: -4, dy: -4).contains(mouse) { return event }
            }
            self.dismiss(); return event
        }
        if let scrollView = anchor.enclosingScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObservation = center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
        }
        if let window = anchor.window {
            for name in [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.willMiniaturizeNotification,
                NSWindow.willCloseNotification,
            ] {
                lifecycleObservations.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.dismiss() }
                })
            }
        }
    }

    private func dismiss(notify: Bool) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let scrollObservation { NotificationCenter.default.removeObserver(scrollObservation); self.scrollObservation = nil }
        lifecycleObservations.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservations.removeAll()
        panel?.orderOut(nil)
        panel = nil; model = nil; anchor = nil
        guard notify else { onDismiss = nil; return }
        let callback = onDismiss; onDismiss = nil; callback?()
    }
}

private struct NotchDropdownMenuContent: View {
    let model: NotchDropdownMenuModel
    private let menuFill = NotchWindowPalette.floating
    private let selectedFill = NotchWindowPalette.floatingSelected
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(model.titles.enumerated()), id: \.offset) { index, title in
                Button { model.select(index) } label: {
                    Text(title)
                        .font(NotchWindowFont.label)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(index == model.highlightedIndex ? selectedFill : menuFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { model.highlight(index) }
                }
                .accessibilityAddTraits(index == model.highlightedIndex ? .isSelected : [])
            }
        }
        .padding(5)
        .background(menuFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NotchWindowPalette.border))
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}
