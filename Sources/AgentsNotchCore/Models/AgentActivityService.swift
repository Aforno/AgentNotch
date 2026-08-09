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
        attentionEvent = nil
        normalizeRestoredIdentities()
        self.sessions.sort(by: Self.orderSessions)
        // Match replaceSessions: seed the temporary attention surface when the
        // caller restores waiting sessions through the initializer.
        attentionEvent = latestWaitingAttentionEvent()
    }

    public var activeSessions: [AgentSession] {
        sessions.filter(\.isActive)
    }

    public var activeGroupCount: Int {
        sessionGroupRoots.filter { groupIsActive(rootID: $0.id) }.count
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

    /// Sessions for the expanded notch list: the three most recently updated
    /// agent groups. Active work still drives the collapsed count, but never
    /// expands this list beyond the explicit three-row presentation policy.
    public var listSessions: [AgentSession] {
        Array(sessionGroupRoots.sorted(by: orderGroupsByRecency).prefix(3))
    }

    private var sessionGroupRoots: [AgentSession] {
        let knownIDs = Set(sessions.map(\.id))
        var roots = hierarchicalSessions.filter { session in
            guard let parentID = session.parentSessionId else { return true }
            return !knownIDs.contains(parentID)
        }
        var covered = Set<String>()
        for root in roots {
            covered.insert(root.id)
            covered.formUnion(descendants(of: root.id).map(\.id))
        }
        // A malformed relationship cycle has no natural root. Promote one
        // member of each uncovered component so active work remains visible.
        for session in hierarchicalSessions where !covered.contains(session.id) {
            roots.append(session)
            covered.insert(session.id)
            covered.formUnion(descendants(of: session.id).map(\.id))
        }
        return roots
    }

    private func groupIsActive(rootID: String) -> Bool {
        sessions.contains { session in
            session.isActive && belongsToGroup(session, rootID: rootID)
        }
    }

    private func belongsToGroup(_ session: AgentSession, rootID: String) -> Bool {
        var current = session
        var visited = Set<String>()
        while visited.insert(current.id).inserted {
            if current.id == rootID { return true }
            guard let parentID = current.parentSessionId,
                  let parent = sessions.first(where: { $0.id == parentID })
            else { return false }
            current = parent
        }
        return false
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
        var event = event
        let now = Date()
        if event.timestamp > now.addingTimeInterval(300) {
            // The socket is local but extensible. A malformed clock must not pin
            // a session in the future and make every later terminal event stale.
            event.timestamp = now
            if event.plan?.updatedAt ?? .distantPast > now {
                event.plan?.updatedAt = now
            }
        }

        event = canonicalizedIdentity(for: event)

        let advancesCurrentState: Bool
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            advancesCurrentState = sessions[index].apply(event)
        } else {
            sessions.append(AgentSession(event: event))
            advancesCurrentState = true
        }

        // A parent may finish before a concurrently delivered child event. Do
        // not create a permanently active child underneath a terminal parent.
        completeSessionIfParentIsTerminal(event.sessionId, at: event.timestamp)

        // SessionEnd/Stop only complete the mapped sessionId. Cascade to active
        // descendants so composite subagent rows do not stay isActive after the
        // parent ends without a per-child SubagentStop.
        let cascadedTerminal = advancesCurrentState
            && (event.resolvedState == .completed || event.resolvedState == .failed)
        if cascadedTerminal {
            completeActiveDescendants(
                of: event.sessionId,
                as: event.resolvedState,
                at: event.timestamp
            )
        }

        sessions.sort(by: Self.orderSessions)
        trimHistory()
        if advancesCurrentState {
            if cascadedTerminal {
                // Rebuild attention: a waiting child may have been cascade-completed.
                attentionEvent = latestWaitingAttentionEvent()
            } else {
                updateAttentionPresentation(for: event)
            }
        }
        onSessionsChanged?(sessions)
    }

    public func replaceSessions(_ sessions: [AgentSession]) {
        self.sessions = sessions
            .filter { !Self.isOrphanedGrokStart($0) }
        normalizeRestoredIdentities()
        self.sessions.sort(by: Self.orderSessions)
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

    /// Hook-driven running sessions cannot be verified after a cold start.
    /// Preserve waiting sessions because the provider may still be blocked on
    /// an approval or answer that will not emit another hook until it is given.
    public func completeUnverifiedActiveSessions() {
        var changed = false
        for index in sessions.indices
            where sessions[index].isActive && sessions[index].state != .waitingForUser
        {
            sessions[index].state = .completed
            sessions[index].completedAt = sessions[index].updatedAt
            changed = true
        }
        guard changed else { return }
        sessions.sort(by: Self.orderSessions)
        trimHistory()
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

    private func completeActiveDescendants(
        of parentID: String,
        as state: AgentState,
        at timestamp: Date
    ) {
        let descendantIDs = Set(descendants(of: parentID).map(\.id))
        guard !descendantIDs.isEmpty else { return }
        for index in sessions.indices
            where descendantIDs.contains(sessions[index].id) && sessions[index].isActive
        {
            sessions[index].state = state
            sessions[index].completedAt = timestamp
            sessions[index].updatedAt = max(sessions[index].updatedAt, timestamp)
            if state == .completed {
                sessions[index].currentActivity = "Session ended"
            } else if state == .failed {
                sessions[index].currentActivity = "Session failed"
            }
        }
    }

    private func completeSessionIfParentIsTerminal(_ sessionID: String, at timestamp: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let parentID = sessions[index].parentSessionId,
              let parent = sessions.first(where: { $0.id == parentID }),
              parent.state == .completed || parent.state == .failed
        else { return }
        sessions[index].completeFromParent(as: parent.state, at: max(parent.updatedAt, timestamp))
    }

    private func canonicalizedIdentity(for event: AgentEvent) -> AgentEvent {
        let collidingIndices = sessions.indices.filter {
            sessions[$0].id == event.sessionId && sessions[$0].provider != event.provider
        }
        guard !collidingIndices.isEmpty else {
            return event
        }
        var event = event
        let prefix = "\(event.provider.rawValue):"
        let originalID = event.sessionId
        for index in collidingIndices {
            let existingProvider = sessions[index].provider
            let existingPrefix = "\(existingProvider.rawValue):"
            let canonicalID = sessions[index].id.hasPrefix(existingPrefix)
                ? sessions[index].id
                : existingPrefix + sessions[index].id
            sessions[index].id = canonicalID
            for childIndex in sessions.indices
                where sessions[childIndex].provider == existingProvider
                    && sessions[childIndex].parentSessionId == originalID
            {
                sessions[childIndex].parentSessionId = canonicalID
            }
            if attentionEvent?.provider == existingProvider,
               attentionEvent?.sessionId == originalID
            {
                attentionEvent?.sessionId = canonicalID
            }
        }
        if !event.sessionId.hasPrefix(prefix) {
            event.sessionId = prefix + event.sessionId
        }
        if let parentID = event.parentSessionId,
           sessions.contains(where: { $0.id == parentID && $0.provider != event.provider }),
           !parentID.hasPrefix(prefix)
        {
            event.parentSessionId = prefix + parentID
        }
        return event
    }

    private func normalizeRestoredIdentities() {
        let providerCounts = Dictionary(grouping: sessions, by: \.id)
            .mapValues { Set($0.map(\.provider)).count }
        let originalIDs = sessions.map(\.id)
        for index in sessions.indices where providerCounts[originalIDs[index], default: 0] > 1 {
            let prefix = "\(sessions[index].provider.rawValue):"
            if !sessions[index].id.hasPrefix(prefix) {
                sessions[index].id = prefix + sessions[index].id
            }
        }
        for index in sessions.indices {
            guard let parentID = sessions[index].parentSessionId,
                  providerCounts[parentID, default: 0] > 1
            else { continue }
            let prefix = "\(sessions[index].provider.rawValue):"
            if !parentID.hasPrefix(prefix) {
                sessions[index].parentSessionId = prefix + parentID
            }
        }

        // Corrupt/legacy history may contain duplicate rows for the same
        // provider identity. Keep the newest snapshot deterministically.
        var newestByIdentity: [String: AgentSession] = [:]
        for session in sessions {
            let key = session.provider.rawValue + "\0" + session.id
            if let existing = newestByIdentity[key], existing.updatedAt >= session.updatedAt {
                continue
            }
            newestByIdentity[key] = session
        }
        sessions = Array(newestByIdentity.values)
    }

    private func orderGroupsByRecency(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsUpdatedAt = ([lhs] + descendants(of: lhs.id)).map(\.updatedAt).max() ?? lhs.updatedAt
        let rhsUpdatedAt = ([rhs] + descendants(of: rhs.id)).map(\.updatedAt).max() ?? rhs.updatedAt
        if lhsUpdatedAt != rhsUpdatedAt { return lhsUpdatedAt > rhsUpdatedAt }
        return lhs.id < rhs.id
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
