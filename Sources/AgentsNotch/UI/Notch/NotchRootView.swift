import AgentsNotchCore
import SwiftUI

private enum NotchPresentation: Equatable {
    case collapsed
    case temporary(String)
    case finished(String)
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
    /// The waiting session the user paged to; falls back to the newest one.
    @State private var pagedAttentionID: String?
    @State private var hoverIntentTask: Task<Void, Never>?
    @State private var outsideClickMonitor = NotchOutsideClickMonitor()
    /// Separate scalars so SwiftUI interpolates width *and* height. A single
    /// optional struct update is easier for the renderer to treat as discrete.
    @State private var drawnWidth: CGFloat = 0
    @State private var drawnHeight: CGFloat = 0
    @State private var drawnRadius: CGFloat = 0
    @State private var hasDrawnLayout = false
    @State private var sizeGeneration = 0
    @State private var detailContentHeight = NotchLayoutMetrics.minimumDetailContentHeight
    @State private var waitingContentHeight = NotchLayoutMetrics.minimumWaitingContentHeight
    /// The top-level session whose completion is briefly announced.
    @State private var finishedFlashID: String?
    @State private var finishedFlashTask: Task<Void, Never>?
    /// 1 at the instant a new prompt arrives, eased to 0: a one-shot glow.
    @State private var attentionGlow: Double = 0
    @AppStorage(AppPreferences.Key.animationsEnabled) private var animationsEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motionEnabled: Bool { animationsEnabled && !reduceMotion }

    private var activity: AgentActivityService { runtime.activity }
    private var snapshot: NotchActivitySnapshot { activity.notchSnapshot }
    private var visibleSessions: [AgentSession] {
        snapshot.listSessions
    }
    private var hasActiveAgents: Bool { !snapshot.activeSessions.isEmpty }

    /// The waiting session shown in the temporary surface. Paging only moves
    /// between sessions that are still waiting.
    private var focusedAttentionSession: AgentSession? {
        snapshot.attentionSessions.first { $0.id == pagedAttentionID } ?? snapshot.attentionSession
    }

    /// Most recently finished top-level session, offered by the empty list.
    private var lastFinishedSession: AgentSession? {
        activity.sessions
            .filter { !$0.isActive && !$0.isSubagent && !$0.isInternalHelper }
            .max { ($0.completedAt ?? $0.updatedAt) < ($1.completedAt ?? $1.updatedAt) }
    }

    private var presentation: NotchPresentation {
        if let selectedSessionID,
           snapshot.relatedSessions.contains(where: { $0.id == selectedSessionID }) {
            return .detail(selectedSessionID)
        }
        if let session = focusedAttentionSession,
           session.pendingReply != nil,
           runtime.canAnswer(session) {
            return .temporary(session.id)
        }
        // Keep the finish action under the pointer until it expires or is
        // clicked, while allowing attention requests to take precedence.
        if focusedAttentionSession == nil,
           let finishedFlashID,
           let session = activity.session(id: finishedFlashID),
           session.state == .completed || session.state == .failed {
            return .finished(finishedFlashID)
        }
        if isHovering { return .list }
        if let session = focusedAttentionSession {
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
            let extraHeight = focusedAttentionSession?.pendingReply == nil
                ? 56
                : NotchLayoutMetrics.waitingContentHeight(
                    measured: waitingContentHeight,
                    screenHeight: geometry.screenFrame.height,
                    notchHeight: geometry.notchHeight
                )
            return NotchLayout(
                width: expandedWidth(preferred: NotchLayoutMetrics.temporaryPreferredWidth),
                height: geometry.notchHeight + extraHeight,
                radius: 18
            )
        case .finished:
            return NotchLayout(
                width: expandedWidth(preferred: NotchLayoutMetrics.finishedPreferredWidth),
                height: geometry.notchHeight + NotchLayoutMetrics.finishedContentHeight,
                radius: 16
            )
        case .list:
            let contentHeight = DynamicIslandSpacing.expandedTop
                + AgentListView.rowsHeight(
                    for: visibleSessions,
                    hiddenGroupCount: snapshot.hiddenActiveGroupCount
                )
                + DynamicIslandSpacing.expandedBottom
            return NotchLayout(
                width: expandedWidth(preferred: NotchLayoutMetrics.listPreferredWidth),
                height: geometry.notchHeight + contentHeight,
                radius: 20
            )
        case .detail:
            return NotchLayout(
                width: expandedWidth(preferred: NotchLayoutMetrics.detailPreferredWidth),
                height: geometry.notchHeight + NotchLayoutMetrics.detailContentHeight(
                    measured: detailContentHeight,
                    screenHeight: geometry.screenFrame.height,
                    notchHeight: geometry.notchHeight
                ),
                radius: 21
            )
        }
    }

    private func expandedWidth(preferred: CGFloat) -> CGFloat {
        NotchLayoutMetrics.expandedWidth(
            preferred: preferred,
            screenWidth: geometry.screenFrame.width,
            notchWidth: geometry.notchWidth
        )
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
            finishedFlashTask?.cancel()
            outsideClickMonitor.stop()
        }
        .onChange(of: snapshot.activeSessions.map(\.id)) { previous, current in
            if let finishedFlashID, current.contains(finishedFlashID) {
                dismissFinishedFlash()
            }
            announceFinishedSession(endedIDs: Set(previous).subtracting(current))
        }
        .onChange(of: selectedSessionID, initial: true) { _, sessionID in
            syncOutsideClickMonitor(isPinned: sessionID != nil)
        }
        .onChange(of: layout) { _, newValue in
            applyLayoutChange(to: newValue)
        }
        .onChange(of: visibleSessions.map(\.id)) { _, _ in
            guard let selectedSessionID,
                  !isVisibleDetailSession(selectedSessionID) else { return }
            self.selectedSessionID = nil
        }
        .onChange(of: snapshot.attentionSessions.map(\.id)) { previous, ids in
            if !Set(ids).subtracting(previous).isEmpty {
                pulseAttention()
            }
            // Forget the paged session once it stops waiting, so a later
            // request from it does not jump ahead of the newest one.
            guard let pagedAttentionID, !ids.contains(pagedAttentionID) else { return }
            self.pagedAttentionID = nil
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
            // No outline: the island should read as part of the bezel, not
            // as a popover. The only edge light is the attention glow.
            NotchShape(bottomRadius: shownRadius)
                .fill(NotchWindowPalette.background)
                .overlay {
                    NotchShape(bottomRadius: shownRadius)
                        .stroke(NotchWindowPalette.attention.opacity(0.9 * attentionGlow), lineWidth: 3)
                        .blur(radius: 2)
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
        case let .finished(id): return "finished-\(id)"
        case .list: return "list"
        case let .detail(id): return "detail-\(id)"
        }
    }

    private var contentTopPadding: CGFloat {
        switch presentation {
        case .collapsed, .list:
            return 0
        case .temporary, .finished, .detail:
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

        if motionEnabled {
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
                    state: collapsedState,
                    activeProviders: snapshot.activeProviders,
                    activeCount: snapshot.activeGroupCount
                )
            }

        case .temporary:
            if let session = focusedAttentionSession {
                if session.pendingReply != nil {
                    WaitingReplyView(
                        session: session,
                        waitingPosition: attentionPosition(of: session),
                        waitingCount: snapshot.attentionCount,
                        onPage: pageAttention,
                        canAnswer: runtime.canAnswer(session),
                        onAnswer: { decision, optionId, answers in
                            runtime.answer(session, decision: decision, optionId: optionId, answers: answers)
                        },
                        onOpenDetail: {
                            withPresentationAnimation { selectedSessionID = session.id }
                        },
                        onIdealHeightChange: { height in
                            guard abs(waitingContentHeight - height) >= 0.5 else { return }
                            waitingContentHeight = height
                        }
                    )
                } else {
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
            }

        case let .finished(id):
            if let session = activity.session(id: id) {
                Button {
                    dismissFinishedFlash()
                    runtime.presentSession(session.id)
                } label: {
                    FinishedFlashView(session: session)
                        .frame(height: NotchLayoutMetrics.finishedContentHeight - DynamicIslandSpacing.expandedTop * 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

        case .list:
            AgentListView(
                sessions: visibleSessions,
                relatedSessions: snapshot.relatedSessions,
                hiddenGroupCount: snapshot.hiddenActiveGroupCount,
                lastFinishedSession: lastFinishedSession,
                topInset: geometry.notchHeight + DynamicIslandSpacing.expandedTop,
                menuBarHeight: geometry.notchHeight,
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
                    onOpen: { runtime.open(session, action: $0) },
                    canAnswer: runtime.canAnswer(session),
                    onAnswer: { decision, optionId, answers in
                        runtime.answer(session, decision: decision, optionId: optionId, answers: answers)
                    },
                    outerCornerRadius: layout.radius,
                    onIdealHeightChange: { height in
                        guard abs(detailContentHeight - height) >= 0.5 else { return }
                        detailContentHeight = height
                    }
                )
            }
        }
    }

    private func updateHoverIntent(_ hovering: Bool) {
        isPointerInside = hovering
        hoverIntentTask?.cancel()
        guard selectedSessionID == nil else {
            // Detail stays pinned after a click so the thread remains readable
            // once the pointer leaves. Back returns to the list only while the
            // pointer is still inside; a click elsewhere collapses the notch.
            isHovering = hovering
            return
        }
        guard hovering != isHovering else { return }

        // Small asymmetric delays prevent the changing panel boundary from
        // producing enter/exit loops while still keeping expansion responsive.
        // Entry waits long enough that a pointer passing on its way to a
        // neighbouring menu bar item does not open the list.
        let delay = hovering ? Duration.milliseconds(150) : .milliseconds(110)
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
        if motionEnabled {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85), change)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, change)
        }
    }

    /// Announces the newest top-level session that just completed or failed.
    /// Subagents and helpers finish constantly and would make this noise.
    private func announceFinishedSession(endedIDs: Set<String>) {
        let finished = endedIDs
            .compactMap { activity.session(id: $0) }
            .filter { !$0.isSubagent && !$0.isInternalHelper }
            .filter { $0.state == .completed || $0.state == .failed }
            .max { $0.updatedAt < $1.updatedAt }
        guard let finished else { return }

        finishedFlashTask?.cancel()
        withPresentationAnimation { finishedFlashID = finished.id }
        finishedFlashTask = Task { @MainActor in
            do {
                try await Task.sleep(for: NotchLayoutMetrics.finishedFlashDuration)
            } catch {
                return
            }
            dismissFinishedFlash()
        }
    }

    private func dismissFinishedFlash() {
        finishedFlashTask?.cancel()
        guard finishedFlashID != nil else { return }
        withPresentationAnimation { finishedFlashID = nil }
    }

    /// One soft orange pass around the island when a new prompt arrives.
    private func pulseAttention() {
        guard motionEnabled else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { attentionGlow = 1 }
        withAnimation(.easeOut(duration: 1.4).delay(0.25)) { attentionGlow = 0 }
    }

    /// Only active states reach the collapsed notch (failed and completed
    /// sessions are not active), so waiting is the one state that outranks
    /// running. `unknown` shows only when no agent is known to be working.
    private var collapsedState: AgentState {
        let states = Set(snapshot.activeSessions.map(\.state))
        if states.contains(.waitingForUser) { return .waitingForUser }
        if states.contains(.unknown), states.count == 1 { return .unknown }
        return .running
    }

    private func attentionPosition(of session: AgentSession) -> Int {
        (snapshot.attentionSessions.firstIndex { $0.id == session.id } ?? 0) + 1
    }

    /// Steps through waiting sessions, wrapping at either end.
    private func pageAttention(by offset: Int) {
        let sessions = snapshot.attentionSessions
        guard sessions.count > 1, let current = focusedAttentionSession else { return }
        let index = sessions.firstIndex { $0.id == current.id } ?? 0
        let next = (index + offset + sessions.count) % sessions.count
        withPresentationAnimation { pagedAttentionID = sessions[next].id }
    }

    private func isVisibleDetailSession(_ sessionID: String) -> Bool {
        snapshot.relatedSessions.contains { $0.id == sessionID }
    }

    private func syncOutsideClickMonitor(isPinned: Bool) {
        if isPinned {
            outsideClickMonitor.start { dismissPinnedDetail() }
        } else {
            outsideClickMonitor.stop()
        }
    }

    private func dismissPinnedDetail() {
        guard selectedSessionID != nil else { return }
        hoverIntentTask?.cancel()
        withPresentationAnimation {
            selectedSessionID = nil
            isHovering = false
            isPointerInside = false
        }
    }
}
