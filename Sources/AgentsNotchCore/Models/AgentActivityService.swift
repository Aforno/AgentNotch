import Darwin
import Foundation
import Observation

public struct NotchActivitySnapshot: Equatable, Sendable {
    public let activeSessions: [AgentSession]
    public let activeProviders: [AgentProvider]
    public let activeGroupCount: Int
    public let attentionSessions: [AgentSession]
    public let attentionSession: AgentSession?
    public let listSessions: [AgentSession]
    public let relatedSessions: [AgentSession]

    public var attentionCount: Int { attentionSessions.count }

    fileprivate static let empty = NotchActivitySnapshot(
        activeSessions: [],
        activeProviders: [],
        activeGroupCount: 0,
        attentionSessions: [],
        attentionSession: nil,
        listSessions: [],
        relatedSessions: []
    )
}

@Observable
@MainActor
public final class AgentActivityService {
    private enum AttentionRefreshPolicy {
        case keep
        case ifMissing
        case always
    }

    public private(set) var sessions: [AgentSession]
    public private(set) var attentionEvent: AgentEvent?
    public private(set) var notchSnapshot: NotchActivitySnapshot
    public private(set) var historyRevision: UInt64
    public var onSessionsChanged: (([AgentSession]) -> Void)?
    @ObservationIgnored private var index: SessionIndex

    public init(sessions: [AgentSession] = []) {
        self.sessions = sessions
            .filter { !Self.isOrphanedGrokStart($0) }
        attentionEvent = nil
        notchSnapshot = .empty
        historyRevision = 0
        index = .empty
        normalizeRestoredIdentities()
        self.sessions.sort(by: Self.orderSessions)
        rebuildIndex()
        // Match replaceSessions: seed the temporary attention surface when the
        // caller restores waiting sessions through the initializer.
        attentionEvent = latestWaitingAttentionEvent()
        publishNotchSnapshot()
    }

    public var activeSessions: [AgentSession] {
        notchSnapshot.activeSessions
    }

    /// Active provider identities ordered by their most recently updated
    /// session. A provider appears once even when it has multiple agents or
    /// subagents running concurrently.
    public var activeProviders: [AgentProvider] {
        notchSnapshot.activeProviders
    }

    public var activeGroupCount: Int {
        notchSnapshot.activeGroupCount
    }

    public var recentSessions: [AgentSession] {
        sessions.filter { !$0.isActive }
    }

    public var attentionSessions: [AgentSession] {
        notchSnapshot.attentionSessions
    }

    public var attentionSession: AgentSession? {
        notchSnapshot.attentionSession
    }

    /// Parent sessions followed by their descendants. A child that needs
    /// attention promotes its whole agent group without losing the hierarchy.
    public var hierarchicalSessions: [AgentSession] {
        _ = sessions
        return index.hierarchicalSessions
    }

    /// Sessions for the expanded notch list: the three most recently updated
    /// agent groups. Active work still drives the collapsed count, but never
    /// expands this list beyond the explicit three-row presentation policy.
    public var listSessions: [AgentSession] {
        notchSnapshot.listSessions
    }

    public func children(of sessionID: String) -> [AgentSession] {
        _ = sessions
        return index.childrenByParentID[sessionID] ?? []
    }

    public func parent(of session: AgentSession) -> AgentSession? {
        guard let parentID = session.parentSessionId else { return nil }
        _ = sessions
        return index.sessionsByID[parentID]
    }

    public func session(id: String) -> AgentSession? {
        _ = sessions
        return index.sessionsByID[id]
    }

    public var attentionCount: Int {
        notchSnapshot.attentionCount
    }

    @discardableResult
    public func ingest(_ event: AgentEvent) -> Bool {
        guard event.protocolVersion == 1 else { return false }
        var event = event
        let now = Date()
        if event.timestamp > now {
            // The socket is local but extensible. Any future skew (not only the
            // extreme >5min case) must not pin updatedAt ahead of wall-clock
            // completions, or later terminal/activity events become "stale".
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

        // Build the session graph after ordering so ordinary activity only
        // pays for one complete projection. A second projection is needed
        // only when parent/descendant reconciliation mutates another row.
        sessions.sort(by: Self.orderSessions)
        rebuildIndex()

        // A parent may finish before a concurrently delivered child event. Do
        // not create a permanently active child underneath a terminal parent.
        var reconciledRelatedSession = completeSessionIfParentIsTerminal(
            event.sessionId,
            at: event.timestamp
        )

        // SessionEnd/Stop only complete the mapped sessionId. Cascade to active
        // descendants so composite subagent rows do not stay isActive after the
        // parent ends without a per-child SubagentStop.
        let cascadedTerminal = advancesCurrentState
            && (event.resolvedState == .completed || event.resolvedState == .failed)
        if cascadedTerminal {
            reconciledRelatedSession = completeActiveDescendants(
                of: event.sessionId,
                as: event.resolvedState,
                at: event.timestamp
            ) || reconciledRelatedSession
        }

        if reconciledRelatedSession {
            sessions.sort(by: Self.orderSessions)
            rebuildIndex()
        }
        if advancesCurrentState {
            if cascadedTerminal {
                // Rebuild attention: a waiting child may have been cascade-completed.
                attentionEvent = latestWaitingAttentionEvent()
            } else {
                updateAttentionPresentation(for: event)
            }
        }
        publishNotchSnapshot()
        notifySessionsChanged()
        return true
    }

    public func replaceSessions(_ sessions: [AgentSession]) {
        self.sessions = sessions
            .filter { !Self.isOrphanedGrokStart($0) }
        normalizeRestoredIdentities()
        // Restoring from disk has no live event stream; rebuild the temporary
        // attention surface from any session that is still waiting for input.
        commitSessionChanges(orderSessions: true, attentionRefresh: .always)
    }

    /// Reconciles workflow metadata discovered from provider-owned storage
    /// without treating app startup as new agent activity.
    public func reconcileRestoredWorkflow(_ event: AgentEvent) {
        guard event.protocolVersion == 1, event.provider == .grok else { return }
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            guard sessions[index].reconcileRestoredWorkflow(event) else { return }
        } else {
            sessions.append(AgentSession(event: event))
        }
        commitSessionChanges(orderSessions: true)
    }

    public func removeSession(id: String) {
        let previousCount = sessions.count
        sessions.removeAll { $0.id == id }
        guard sessions.count != previousCount else { return }
        commitSessionChanges(attentionRefresh: .ifMissing)
    }

    public func removeSessions(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousCount = sessions.count
        sessions.removeAll { ids.contains($0.id) }
        guard sessions.count != previousCount else { return }
        commitSessionChanges(attentionRefresh: .ifMissing)
    }

    public func clearRecent() {
        let previousCount = sessions.count
        sessions.removeAll { !$0.isActive }
        guard sessions.count != previousCount else { return }
        commitSessionChanges(attentionRefresh: .ifMissing)
    }

    public func pruneCompleted(olderThan age: TimeInterval, now: Date = Date()) {
        let previousCount = sessions.count
        sessions.removeAll { session in
            guard let completedAt = session.completedAt else { return false }
            return now.timeIntervalSince(completedAt) > age
        }
        guard sessions.count != previousCount else { return }
        commitSessionChanges(attentionRefresh: .ifMissing)
    }

    /// Reconciles hook-driven sessions after a cold start.
    ///
    /// Waiting sessions are preserved: the provider may still be blocked on an
    /// approval that will not emit another hook until the user answers.
    /// When `origin.processIdentifier` is present and the process is gone, the
    /// session is completed immediately. Remaining unverified actives become
    /// `.unknown` (reconnecting) instead of inventing a completion; a later
    /// live event or grace-period expiry resolves them.
    public func reconcileUnverifiedActiveSessions(
        processAlive: (Int32) -> Bool = { pid in
            guard pid > 0 else { return false }
            return kill(pid, 0) == 0
        }
    ) {
        var changed = false
        for index in sessions.indices
            where sessions[index].isActive && sessions[index].state != .waitingForUser
        {
            if sessions[index].state == .unknown {
                continue
            }
            if let pid = sessions[index].origin?.processIdentifier, !processAlive(pid) {
                let completedAt = sessions[index].updatedAt
                let parentID = sessions[index].id
                sessions[index].complete(as: .completed, at: completedAt)
                // Match ingest: active/waiting children under a terminal parent
                // must not linger as attention pins after the origin dies.
                completeActiveDescendants(of: parentID, as: .completed, at: completedAt)
                changed = true
                continue
            }
            sessions[index].markUnknown()
            changed = true
        }
        guard changed else { return }
        commitSessionChanges(orderSessions: true, attentionRefresh: .always)
    }

    /// Completes sessions still stuck in `.unknown` after the reconnect grace
    /// period when no live hook arrived to confirm they are still running.
    public func completeUnknownSessions() {
        var changed = false
        for index in sessions.indices where sessions[index].state == .unknown {
            sessions[index].complete(as: .completed, at: sessions[index].updatedAt)
            changed = true
        }
        guard changed else { return }
        commitSessionChanges(orderSessions: true, attentionRefresh: .always)
    }

    /// Applies provider-owned restore evidence (e.g. Grok workflow status) to a
    /// session that is still in `.unknown` after cold-start reconciliation.
    public func applyRestoredLifecycle(
        sessionId: String,
        state: AgentState,
        activity: String?,
        at timestamp: Date
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard sessions[index].applyRestoredLifecycle(
            state: state,
            activity: activity,
            at: timestamp
        ) else { return }
        commitSessionChanges(orderSessions: true, attentionRefresh: .always)
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
        index.attentionSessions.first.map(attentionEvent(for:))
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

    @discardableResult
    private func completeActiveDescendants(
        of parentID: String,
        as state: AgentState,
        at timestamp: Date
    ) -> Bool {
        let descendantIDs = index.descendantIDs(of: parentID)
        guard !descendantIDs.isEmpty else { return false }
        var completedAny = false
        for index in sessions.indices
            where descendantIDs.contains(sessions[index].id) && sessions[index].isActive
        {
            sessions[index].complete(as: state, at: timestamp)
            completedAny = true
        }
        return completedAny
    }

    private func completeSessionIfParentIsTerminal(_ sessionID: String, at timestamp: Date) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].isActive,
              let parentID = sessions[index].parentSessionId,
              let parent = sessions.first(where: { $0.id == parentID }),
              parent.state == .completed || parent.state == .failed
        else { return false }
        sessions[index].complete(as: parent.state, at: max(parent.updatedAt, timestamp))
        return true
    }

    private func canonicalizedIdentity(for incomingEvent: AgentEvent) -> AgentEvent {
        let prefix = "\(incomingEvent.provider.rawValue):"
        // After a prior cross-provider collision, rows are stored as provider:id.
        // Later events still carrying the bare id must resolve to that row
        // instead of creating a duplicate unprefixed session.
        if let resolved = eventTargetingExistingCanonicalSession(
            incomingEvent,
            providerPrefix: prefix
        ) {
            return resolved
        }

        let collidingIndices = sessions.indices.filter {
            sessions[$0].id == incomingEvent.sessionId
                && sessions[$0].provider != incomingEvent.provider
        }
        guard !collidingIndices.isEmpty else { return incomingEvent }

        renameCollidingSessions(at: collidingIndices, originalID: incomingEvent.sessionId)
        return eventCanonicalizedAfterCollision(incomingEvent, providerPrefix: prefix)
    }

    private func eventTargetingExistingCanonicalSession(
        _ event: AgentEvent,
        providerPrefix: String
    ) -> AgentEvent? {
        guard !event.sessionId.hasPrefix(providerPrefix) else { return nil }
        let canonicalID = providerPrefix + event.sessionId
        guard sessions.contains(where: {
            $0.id == canonicalID && $0.provider == event.provider
        }) else { return nil }

        var resolved = event
        resolved.sessionId = canonicalID
        if let parentID = event.parentSessionId,
           !parentID.hasPrefix(providerPrefix),
           sessions.contains(where: {
               $0.id == providerPrefix + parentID && $0.provider == event.provider
           })
        {
            resolved.parentSessionId = providerPrefix + parentID
        }
        return resolved
    }

    private func renameCollidingSessions(
        at indices: [Int],
        originalID: String
    ) {
        for index in indices {
            let existingProvider = sessions[index].provider
            let existingPrefix = "\(existingProvider.rawValue):"
            let canonicalID = sessions[index].id.hasPrefix(existingPrefix)
                ? sessions[index].id
                : existingPrefix + sessions[index].id
            sessions[index].id = canonicalID
            // Keep recentEvents (and attentionEvent(for:)) on the renamed id so
            // waiting attention cannot surface a stale bare sessionId.
            for eventIndex in sessions[index].recentEvents.indices
                where sessions[index].recentEvents[eventIndex].sessionId == originalID
            {
                sessions[index].recentEvents[eventIndex].sessionId = canonicalID
            }
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
    }

    private func eventCanonicalizedAfterCollision(
        _ event: AgentEvent,
        providerPrefix: String
    ) -> AgentEvent {
        var event = event
        if !event.sessionId.hasPrefix(providerPrefix) {
            event.sessionId = providerPrefix + event.sessionId
        }
        if let parentID = event.parentSessionId,
           sessions.contains(where: { $0.id == parentID && $0.provider != event.provider }),
           !parentID.hasPrefix(providerPrefix)
        {
            event.parentSessionId = providerPrefix + parentID
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

    private func rebuildIndex() {
        index = SessionIndex(sessions: sessions)
    }

    /// Finishes a successful session mutation through the single publication
    /// path used by history, attention, and notch consumers.
    private func commitSessionChanges(
        orderSessions: Bool = false,
        attentionRefresh: AttentionRefreshPolicy = .keep
    ) {
        if orderSessions {
            sessions.sort(by: Self.orderSessions)
        }
        rebuildIndex()
        switch attentionRefresh {
        case .keep:
            break
        case .ifMissing where attentionEvent.map({ index.sessionsByID[$0.sessionId] == nil }) != true:
            break
        case .ifMissing, .always:
            attentionEvent = latestWaitingAttentionEvent()
        }
        publishNotchSnapshot()
        notifySessionsChanged()
    }

    private func publishNotchSnapshot() {
        let snapshot = index.notchSnapshot(attentionEvent: attentionEvent)
        if snapshot != notchSnapshot {
            notchSnapshot = snapshot
        }
    }

    private func notifySessionsChanged() {
        historyRevision &+= 1
        onSessionsChanged?(sessions)
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
