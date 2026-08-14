import AgentsNotchCore
import SwiftUI

private enum NotchPresentation: Equatable {
    case collapsed
    case temporary(String)
    case list
    case detail(String)
}

private struct NotchLayout: Equatable {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
}

@MainActor
private extension AnyTransition {
    /// Content inside the notch fades through a light blur and settles from a
    /// subtle scale, echoing the Dynamic Island's material feel.
    static let notchContent: AnyTransition = .asymmetric(
        insertion: .opacity
            .combined(with: .scale(scale: 0.96, anchor: .top))
            .combined(with: .modifier(
                active: NotchBlurModifier(radius: 6),
                identity: NotchBlurModifier(radius: 0)
            )),
        removal: .opacity
            .combined(with: .modifier(
                active: NotchBlurModifier(radius: 8),
                identity: NotchBlurModifier(radius: 0)
            ))
    )
}

private struct NotchBlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
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
    private var snapshot: NotchActivitySnapshot { activity.notchSnapshot }
    private var visibleSessions: [AgentSession] {
        snapshot.listSessions
    }
    private var hasActiveAgents: Bool { !snapshot.activeSessions.isEmpty }

    private var presentation: NotchPresentation {
        if let selectedSessionID,
           snapshot.relatedSessions.contains(where: { $0.id == selectedSessionID }) {
            return .detail(selectedSessionID)
        }
        if isHovering { return .list }
        if let session = snapshot.attentionSession {
            return .temporary(session.id)
        }
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
                    width: geometry.notchWidth
                    + DynamicIslandSpacing.compactEarWidth(for: snapshot.activeGroupCount) * 2,
                height: geometry.notchHeight + 2,
                radius: min(10, (geometry.notchHeight + 2) * 0.32)
            )
        case .temporary:
            return NotchLayout(width: 392, height: geometry.notchHeight + 56, radius: 18)
        case .list:
            let contentHeight = DynamicIslandSpacing.expandedTop
                + AgentListView.rowsHeight(for: visibleSessions)
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
        .onChange(of: visibleSessions.map(\.id)) { _, _ in
            guard let selectedSessionID,
                  !isVisibleDetailSession(selectedSessionID) else { return }
            self.selectedSessionID = nil
        }
        .onChange(of: runtime.requestedSessionID) { _, sessionID in
            guard let sessionID,
                  snapshot.relatedSessions.contains(where: { $0.id == sessionID }) else { return }
            withPresentationAnimation { selectedSessionID = sessionID }
            runtime.consumeRequestedSession(sessionID)
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
                .transition(.notchContent)
                .id(contentTransitionID)
        }
        .frame(width: shownWidth, height: shownHeight, alignment: .top)
        .clipShape(NotchShape(bottomRadius: shownRadius))
        .contentShape(NotchShape(bottomRadius: shownRadius))
    }

    /// Identity for the morphing content so presentation changes cross-fade
    /// (blur + scale) instead of snapping between subtrees.
    private var contentTransitionID: String {
        switch presentation {
        case .collapsed: return "collapsed"
        case .temporary: return "temporary"
        case .list: return "list"
        case let .detail(id): return "detail-\(id)"
        }
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
            // A gentle spring reads as "Dynamic Island": a hint of overshoot
            // when growing, and a slightly tighter, faster settle when
            // shrinking so collapse never feels bouncy.
            let animation: Animation = expanding
                ? .spring(response: 0.38, dampingFraction: 0.78)
                : .spring(response: 0.30, dampingFraction: 0.92)
            withAnimation(animation) {
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
                CollapsedNotchView(
                    activeProviders: snapshot.activeProviders,
                    activeCount: snapshot.activeGroupCount
                )
            }

        case .temporary:
            if let session = snapshot.attentionSession {
                Button {
                    withPresentationAnimation { selectedSessionID = session.id }
                } label: {
                    TemporaryActivityView(
                        session: session,
                        waitingCount: snapshot.attentionCount
                    )
                        .frame(height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

        case .list:
            AgentListView(
                sessions: visibleSessions,
                relatedSessions: snapshot.relatedSessions,
                topInset: geometry.notchHeight + DynamicIslandSpacing.expandedTop,
                onOpenSettings: { runtime.openSettings() },
                onOpenActivityCenter: { runtime.openActivityCenter() },
                onSelect: { id in
                    withPresentationAnimation { selectedSessionID = id }
                }
            )

        case let .detail(id):
            if let session = snapshot.relatedSessions.first(where: { $0.id == id }) {
                AgentDetailView(
                    session: session,
                    parent: session.parentSessionId.flatMap { parentID in
                        snapshot.relatedSessions.first(where: { $0.id == parentID })
                    },
                    children: snapshot.relatedSessions
                        .filter { $0.parentSessionId == session.id }
                        .sorted { $0.updatedAt > $1.updatedAt },
                    onBack: { withPresentationAnimation { selectedSessionID = nil } },
                    onSelectSession: { id in withPresentationAnimation { selectedSessionID = id } },
                    onOpen: { runtime.open(session) }
                )
            }
        }
    }

    private func updateHoverIntent(_ hovering: Bool) {
        isPointerInside = hovering
        hoverIntentTask?.cancel()
        guard selectedSessionID == nil else {
            // Detail presentation masks hover presentation. Still track the
            // pointer so Back returns to list only while the pointer is inside.
            isHovering = hovering
            return
        }
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
            withPresentationAnimation {
                isHovering = hovering
            }
        }
    }

    /// Presentation is derived state, so the swap between content subtrees
    /// only animates when the state driving it changes inside a transaction.
    private func withPresentationAnimation(_ change: () -> Void) {
        if animationsEnabled {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85), change)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, change)
        }
    }

    private func isVisibleDetailSession(_ sessionID: String) -> Bool {
        snapshot.relatedSessions.contains { $0.id == sessionID }
    }
}
