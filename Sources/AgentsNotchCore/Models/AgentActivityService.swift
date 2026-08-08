import Foundation
import Observation

@Observable
@MainActor
public final class AgentActivityService {
    public private(set) var sessions: [AgentSession]
    public private(set) var attentionEvent: AgentEvent?
    public var onSessionsChanged: (([AgentSession]) -> Void)?

    public init(sessions: [AgentSession] = []) {
        self.sessions = sessions
            .filter { !Self.isOrphanedGrokStart($0) }
            .sorted(by: Self.orderSessions)
    }

    public var activeSessions: [AgentSession] {
        sessions.filter(\.isActive)
    }

    public var recentSessions: [AgentSession] {
        sessions.filter { !$0.isActive }
    }

    /// Parent sessions followed by their descendants. A child that needs
    /// attention promotes its whole agent group without losing the hierarchy.
    public var hierarchicalSessions: [AgentSession] {
        let knownIDs = Set(sessions.map(\.id))
        let roots = sessions
            .filter { session in
                guard let parentID = session.parentSessionId else { return true }
                return !knownIDs.contains(parentID)
            }
            .sorted(by: orderAgentGroups)

        var result: [AgentSession] = []
        var visited: Set<String> = []
        for root in roots {
            appendHierarchy(from: root, to: &result, visited: &visited)
        }
        // Malformed external input can contain a relationship cycle. Keep those
        // sessions visible as roots instead of recursing forever or dropping them.
        for session in sessions where !visited.contains(session.id) {
            appendHierarchy(from: session, to: &result, visited: &visited)
        }
        return result
    }

    /// Sessions for the expanded notch list: the latest 3 (active sessions
    /// count toward that cap). When more than 3 are active, every active
    /// session is shown so concurrent work is never hidden.
    ///
    /// Inactive children are allowed to fill remaining slots, but they must
    /// not consume the budget that belongs to concurrent active sessions.
    public var listSessions: [AgentSession] {
        let hierarchical = hierarchicalSessions
        let activeIDs = Set(hierarchical.filter(\.isActive).map(\.id))
        let limit = max(3, activeIDs.count)
        var inactiveSlots = limit - activeIDs.count
        var result: [AgentSession] = []
        result.reserveCapacity(limit)

        for session in hierarchical {
            if activeIDs.contains(session.id) {
                result.append(session)
            } else if inactiveSlots > 0 {
                result.append(session)
                inactiveSlots -= 1
            }
        }
        return result
    }

    public func children(of sessionID: String) -> [AgentSession] {
        sessions.filter { $0.parentSessionId == sessionID }.sorted(by: Self.orderSessions)
    }

    public func parent(of session: AgentSession) -> AgentSession? {
        guard let parentID = session.parentSessionId else { return nil }
        return sessions.first { $0.id == parentID }
    }

    public var attentionCount: Int {
        sessions.filter(\.needsAttention).count
    }

    public func ingest(_ event: AgentEvent) {
        guard event.protocolVersion == 1 else { return }

        let advancesCurrentState: Bool
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            advancesCurrentState = sessions[index].apply(event)
        } else {
            sessions.append(AgentSession(event: event))
            advancesCurrentState = true
        }

        sessions.sort(by: Self.orderSessions)
        trimHistory()
        if advancesCurrentState {
            updateAttentionPresentation(for: event)
        }
        onSessionsChanged?(sessions)
    }

    public func replaceSessions(_ sessions: [AgentSession]) {
        self.sessions = sessions
            .filter { !Self.isOrphanedGrokStart($0) }
            .sorted(by: Self.orderSessions)
        trimHistory()
        // Restoring from disk has no live event stream; rebuild the temporary
        // attention surface from any session that is still waiting for input.
        attentionEvent = latestWaitingAttentionEvent()
    }

    public func removeSession(id: String) {
        sessions.removeAll { $0.id == id }
        if attentionEvent?.sessionId == id {
            attentionEvent = latestWaitingAttentionEvent()
        }
        onSessionsChanged?(sessions)
    }

    public func removeSessions(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousCount = sessions.count
        sessions.removeAll { ids.contains($0.id) }
        guard sessions.count != previousCount else { return }
        if let attentionEvent, ids.contains(attentionEvent.sessionId) {
            self.attentionEvent = latestWaitingAttentionEvent()
        }
        onSessionsChanged?(sessions)
    }

    public func clearRecent() {
        sessions.removeAll { !$0.isActive }
        onSessionsChanged?(sessions)
    }

    public func pruneCompleted(olderThan age: TimeInterval, now: Date = Date()) {
        sessions.removeAll { session in
            guard let completedAt = session.completedAt else { return false }
            return now.timeIntervalSince(completedAt) > age
        }
        onSessionsChanged?(sessions)
    }

    /// Hook-driven sessions cannot be verified after a cold start: adapters do
    /// not poll provider processes. Mark restored actives completed so a missed
    /// Stop/SessionEnd cannot leave rows active forever. Later hook events
    /// resume a session if the agent is still live.
    public func completeUnverifiedActiveSessions() {
        var changed = false
        for index in sessions.indices where sessions[index].isActive {
            sessions[index].state = .completed
            sessions[index].completedAt = sessions[index].updatedAt
            changed = true
        }
        guard changed else { return }
        sessions.sort(by: Self.orderSessions)
        attentionEvent = latestWaitingAttentionEvent()
        onSessionsChanged?(sessions)
    }

    private func updateAttentionPresentation(for event: AgentEvent) {
        if event.resolvedState == .waitingForUser {
            // Always rank by session recency so a late/older waiter cannot
            // steal the temporary presentation from a more recent one.
            attentionEvent = latestWaitingAttentionEvent()
            return
        }
        // When the currently presented agent resumes, fall back to any other
        // session that is still waiting rather than clearing attention entirely.
        if attentionEvent?.sessionId == event.sessionId {
            attentionEvent = latestWaitingAttentionEvent()
        }
    }

    /// Most recently updated session still waiting for the user, as an event
    /// suitable for the temporary notch presentation.
    private func latestWaitingAttentionEvent() -> AgentEvent? {
        sessions
            .filter { $0.state == .waitingForUser }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
            .map(attentionEvent(for:))
    }

    private func attentionEvent(for session: AgentSession) -> AgentEvent {
        if let event = session.recentEvents.first(where: { $0.resolvedState == .waitingForUser }) {
            return event
        }
        return AgentEvent(
            type: .waiting,
            sessionId: session.id,
            provider: session.provider,
            task: session.task,
            activity: session.currentActivity,
            state: .waitingForUser,
            timestamp: session.updatedAt,
            workingDirectory: session.workingDirectory,
            applicationURL: session.applicationURL,
            parentSessionId: session.parentSessionId,
            agentRole: session.agentRole
        )
    }

    private func trimHistory() {
        let active = sessions.filter(\.isActive)
        let recent = sessions.filter { !$0.isActive }.prefix(20)
        sessions = (active + recent).sorted(by: Self.orderSessions)
    }

    private func appendHierarchy(
        from session: AgentSession,
        to result: inout [AgentSession],
        visited: inout Set<String>
    ) {
        guard visited.insert(session.id).inserted else { return }
        result.append(session)
        for child in children(of: session.id) {
            appendHierarchy(from: child, to: &result, visited: &visited)
        }
    }

    private func orderAgentGroups(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsGroup = [lhs] + descendants(of: lhs.id)
        let rhsGroup = [rhs] + descendants(of: rhs.id)
        let lhsNeedsAttention = lhsGroup.contains(where: \.needsAttention)
        let rhsNeedsAttention = rhsGroup.contains(where: \.needsAttention)
        if lhsNeedsAttention != rhsNeedsAttention { return lhsNeedsAttention }
        let lhsIsActive = lhsGroup.contains(where: \.isActive)
        let rhsIsActive = rhsGroup.contains(where: \.isActive)
        if lhsIsActive != rhsIsActive { return lhsIsActive }
        let lhsUpdatedAt = lhsGroup.map(\.updatedAt).max() ?? lhs.updatedAt
        let rhsUpdatedAt = rhsGroup.map(\.updatedAt).max() ?? rhs.updatedAt
        return lhsUpdatedAt > rhsUpdatedAt
    }

    private func descendants(of sessionID: String) -> [AgentSession] {
        var result: [AgentSession] = []
        var pending = [sessionID]
        var visited = Set(pending)
        while let parentID = pending.popLast() {
            for child in sessions where child.parentSessionId == parentID && visited.insert(child.id).inserted {
                result.append(child)
                pending.append(child.id)
            }
        }
        return result
    }

    private static func orderSessions(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        return lhs.updatedAt > rhs.updatedAt
    }

    /// Removes rows persisted by older builds when Grok initialized a command
    /// but never began an agent turn. Real Grok sessions have at least one
    /// prompt, tool, notification, or terminal event after SessionStart.
    private static func isOrphanedGrokStart(_ session: AgentSession) -> Bool {
        guard session.provider == .grok,
              session.state == .starting,
              !session.recentEvents.isEmpty
        else { return false }

        return session.recentEvents.allSatisfy { event in
            guard event.type == .started,
                  let hookEvent = event.metadata?["hookEvent"]
            else { return false }
            return hookEvent
                .replacingOccurrences(of: "_", with: "")
                .lowercased() == "sessionstart"
        }
    }
}
