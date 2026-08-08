import AgentsNotchCore
import SwiftUI

private enum NotchPresentation: Equatable {
    case collapsed
    case temporary(UUID)
    case list
    case detail(String)
}

private struct NotchLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
}

struct NotchRootView: View {
    let runtime: AppRuntime
    let geometry: DisplayGeometry
    let onSizeChange: (CGSize, Bool) -> Void

    @State private var isHovering = false
    @State private var isPointerInside = false
    @State private var selectedSessionID: String?
    @State private var hoverIntentTask: Task<Void, Never>?
    /// Separate scalars so SwiftUI interpolates width *and* height. A single
    /// optional struct update is easier for the renderer to treat as discrete.
    @State private var drawnWidth: CGFloat = 0
    @State private var drawnHeight: CGFloat = 0
    @State private var drawnRadius: CGFloat = 0
    @State private var hasDrawnLayout = false
    @State private var sizeGeneration = 0
    @AppStorage("animationsEnabled") private var animationsEnabled = true

    private var activity: AgentActivityService { runtime.activity }
    private var visibleSessions: [AgentSession] {
        activity.listSessions
    }
    private var hasActiveAgents: Bool { !activity.activeSessions.isEmpty }

    private var presentation: NotchPresentation {
        if let selectedSessionID,
           activity.sessions.contains(where: { $0.id == selectedSessionID }) {
            return .detail(selectedSessionID)
        }
        if isHovering { return .list }
        if let event = activity.attentionEvent { return .temporary(event.id) }
        return .collapsed
    }

    private var layout: NotchLayout {
        switch presentation {
        case .collapsed:
            // With nothing running, disappear into the physical notch. Active
            // agents keep the wider side ears that hold their status controls.
            if !hasActiveAgents {
                return NotchLayout(
                    width: geometry.notchWidth,
                    height: geometry.notchHeight,
                    radius: min(10, geometry.notchHeight * 0.32)
                )
            }
            return NotchLayout(
                width: geometry.notchWidth + DynamicIslandSpacing.compactEarWidth * 2,
                height: geometry.notchHeight + 2,
                radius: min(10, (geometry.notchHeight + 2) * 0.32)
            )
        case .temporary:
            return NotchLayout(width: 370, height: geometry.notchHeight + 48, radius: 18)
        case .list:
            let count = max(visibleSessions.count, 1)
            let contentHeight = DynamicIslandSpacing.expandedTop
                + CGFloat(count) * DynamicIslandSpacing.rowHeight
                + DynamicIslandSpacing.expandedBottom
            return NotchLayout(width: 424, height: geometry.notchHeight + contentHeight, radius: 20)
        case .detail:
            return NotchLayout(width: 440, height: geometry.notchHeight + 322, radius: 21)
        }
    }

    private var shownWidth: CGFloat { hasDrawnLayout ? drawnWidth : layout.width }
    private var shownHeight: CGFloat { hasDrawnLayout ? drawnHeight : layout.height }
    private var shownRadius: CGFloat { hasDrawnLayout ? drawnRadius : layout.radius }

    var body: some View {
        // Explicit width/height so SwiftUI interpolates both axes. The AppKit
        // panel is expanded to the union of from/to sizes for the duration of
        // the morph (so height is never clipped), then settled to the final
        // size when the animation completes.
        GeometryReader { container in
            notchSurface
                // The AppKit panel snaps to the union of the old and new
                // sizes before the SwiftUI morph starts. Pin the surface to
                // that container's horizontal center explicitly; relying on
                // layout alignment here lets the leading edge follow the
                // panel snap while only the trailing edge interpolates.
                .position(
                    x: container.size.width / 2,
                    y: shownHeight / 2
                )
                .onHover { hovering in
                    updateHoverIntent(hovering)
                }
        }
        // This panel is itself the top-of-screen overlay; system safe-area
        // insets would push the black shape down and reveal the menu bar.
        .ignoresSafeArea()
        .onAppear {
            applyDrawnLayout(layout, animated: false)
            onSizeChange(CGSize(width: layout.width, height: layout.height), false)
        }
        .onDisappear {
            hoverIntentTask?.cancel()
        }
        .onChange(of: layout) { _, newValue in
            applyLayoutChange(to: newValue)
        }
        .onChange(of: activity.sessions.map(\.id)) { _, sessionIDs in
            guard let selectedSessionID,
                  !sessionIDs.contains(selectedSessionID) else { return }
            self.selectedSessionID = nil
        }
        .accessibilityElement(children: .contain)
    }

    private var notchSurface: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: shownRadius)
                .fill(Color.black.opacity(0.985))
                .overlay {
                    NotchShape(bottomRadius: shownRadius)
                        .stroke(Color.white.opacity(presentation == .collapsed ? 0 : 0.08), lineWidth: 0.6)
                }

            content
                .padding(.top, contentTopPadding)
        }
        .frame(width: shownWidth, height: shownHeight, alignment: .top)
        .clipShape(NotchShape(bottomRadius: shownRadius))
        .contentShape(NotchShape(bottomRadius: shownRadius))
    }

    private var contentTopPadding: CGFloat {
        switch presentation {
        case .collapsed, .list:
            return 0
        case .temporary, .detail:
            return geometry.notchHeight + DynamicIslandSpacing.expandedTop
        }
    }

    private func applyLayoutChange(to newValue: NotchLayout) {
        let from = NotchLayout(
            width: shownWidth,
            height: shownHeight,
            radius: shownRadius
        )
        guard from != newValue else { return }

        sizeGeneration += 1
        let generation = sizeGeneration

        if animationsEnabled {
            // Room for the entire morph up front — otherwise the panel would
            // clip the growing height before SwiftUI can draw it.
            let container = CGSize(
                width: max(from.width, newValue.width),
                height: max(from.height, newValue.height)
            )
            onSizeChange(container, false)

            let expanding = newValue.width > from.width || newValue.height > from.height
            withAnimation(.easeInOut(duration: expanding ? 0.24 : 0.19)) {
                applyDrawnLayout(newValue, animated: true)
            } completion: {
                guard generation == sizeGeneration else { return }
                onSizeChange(CGSize(width: newValue.width, height: newValue.height), false)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                applyDrawnLayout(newValue, animated: false)
            }
            onSizeChange(CGSize(width: newValue.width, height: newValue.height), false)
        }
    }

    private func applyDrawnLayout(_ layout: NotchLayout, animated: Bool) {
        _ = animated
        drawnWidth = layout.width
        drawnHeight = layout.height
        drawnRadius = layout.radius
        hasDrawnLayout = true
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .collapsed:
            if hasActiveAgents {
                CollapsedNotchView(sessions: activity.activeSessions)
            }

        case .temporary:
            if let event = activity.attentionEvent {
                Button {
                    guard activity.sessions.contains(where: { $0.id == event.sessionId }) else { return }
                    selectedSessionID = event.sessionId
                } label: {
                    TemporaryActivityView(event: event)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

        case .list:
            AgentListView(
                sessions: visibleSessions,
                topInset: geometry.notchHeight + DynamicIslandSpacing.expandedTop,
                onOpenSettings: { runtime.openSettings() },
                onSelect: { id in
                    selectedSessionID = id
                }
            )

        case let .detail(id):
            if let session = activity.sessions.first(where: { $0.id == id }) {
                AgentDetailView(
                    session: session,
                    parent: activity.parent(of: session),
                    children: activity.children(of: session.id),
                    onBack: { selectedSessionID = nil },
                    onSelectSession: { selectedSessionID = $0 },
                    onOpen: { runtime.open(session) }
                )
            }
        }
    }

    private func updateHoverIntent(_ hovering: Bool) {
        isPointerInside = hovering
        hoverIntentTask?.cancel()
        guard selectedSessionID == nil else { return }
        guard hovering != isHovering else { return }

        // Small asymmetric delays prevent the changing panel boundary from
        // producing enter/exit loops while still keeping expansion responsive.
        let delay = hovering ? Duration.milliseconds(60) : .milliseconds(110)
        hoverIntentTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, isPointerInside == hovering else { return }
            isHovering = hovering
        }
    }
}
