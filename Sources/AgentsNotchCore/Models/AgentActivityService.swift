import Darwin
import Foundation
import Observation
import os

public struct NotchActivitySnapshot: Equatable, Sendable {
    public let activeSessions: [AgentSession]
    public let activeProviders: [AgentProvider]
    public let activeGroupCount: Int
    public let attentionSessions: [AgentSession]
    public let attentionSession: AgentSession?
    public let listSessions: [AgentSession]
    public let relatedSessions: [AgentSession]
    /// Active agent groups beyond the expanded list's presentation cap, so the
    /// collapsed count and expanded rows never disagree silently.
    public let hiddenActiveGroupCount: Int

    public var attentionCount: Int { attentionSessions.count }

    fileprivate static let empty = NotchActivitySnapshot(
        activeSessions: [],
        activeProviders: [],
        activeGroupCount: 0,
        attentionSessions: [],
        attentionSession: nil,
        listSessions: [],
        relatedSessions: [],
        hiddenActiveGroupCount: 0
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
    /// Set when an event arrived with an unsupported `protocolVersion`. Such
    /// events are dropped, so this flag is the only user-visible trace — the
    /// classic stale-relay-after-app-upgrade scenario.
    public private(set) var protocolMismatchDetected = false
    public var onSessionsChanged: (([AgentSession]) -> Void)?
    private var index: SessionIndex
    private var sessionsByID: [String: Int]
    private static let logger = Logger(subsystem: "com.afonsoferreira.AgentNotch", category: "activity")

    public init(sessions: [AgentSession] = []) {
        self.sessions = sessions
        attentionEvent = nil
        notchSnapshot = .empty
        historyRevision = 0
        index = .empty
        sessionsByID = [:]
        normalizeRestoredSessions()
        self.sessions.sort(by: Self.orderSessions)
        rebuildLookups()
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
        index.hierarchicalSessions
    }

    /// Sessions for the expanded notch list: the three most recently updated
    /// agent groups. Active work still drives the collapsed count, but never
    /// expands this list beyond the explicit three-row presentation policy.
    public var listSessions: [AgentSession] {
        notchSnapshot.listSessions
    }

    public func children(of sessionID: String) -> [AgentSession] {
        index.childrenByParentID[sessionID] ?? []
    }

    public func parent(of session: AgentSession) -> AgentSession? {
        guard let parentID = session.parentSessionId else { return nil }
        return index.sessionsByID[parentID]
    }

    public func session(id: String) -> AgentSession? {
        index.sessionsByID[id]
    }

    public var attentionCount: Int {
        notchSnapshot.attentionCount
    }

    @discardableResult
    public func ingest(_ event: AgentEvent) -> Bool {
        guard event.protocolVersion == 1 else {
            protocolMismatchDetected = true
            Self.logger.error(
                "Dropped event for session \(event.sessionId, privacy: .private): protocol version \(event.protocolVersion) is not supported (expected 1). Reinstall provider integrations or update the app."
            )
            return false
        }
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

        var createdSession = false
        let advancesCurrentState: Bool
        if let existingIndex = sessionsByID[event.sessionId] {
            advancesCurrentState = sessions[existingIndex].apply(event)
        } else {
            sessions.append(AgentSession(event: event))
            sessionsByID[event.sessionId] = sessions.count - 1
            advancesCurrentState = true
            createdSession = true
        }

        // A parent may finish before a concurrently delivered child event. Do
        // not create a permanently active child underneath a terminal parent.
        // Tree edges are unchanged here, so the current SessionIndex is valid
        // for descendant lookup; rebuild once after every mutation.
        let completedByParentRule = completeSessionIfParentIsTerminal(
            event.sessionId,
            at: event.timestamp
        )

        // SessionEnd/Stop only complete the mapped sessionId. Cascade to active
        // descendants so composite subagent rows do not stay isActive after the
        // parent ends without a per-child SubagentStop.
        let cascadedTerminal = advancesCurrentState
            && (event.resolvedState == .completed || event.resolvedState == .failed)
        if cascadedTerminal {
            _ = completeActiveDescendants(
                of: event.sessionId,
                as: event.resolvedState,
                at: event.timestamp
            )
        }

        // Ordering and the presentation index only change when state, recency,
        // membership, parent links, or the task (housekeeping classification)
        // changed. Late tool/file/workflow echoes on an unchanged session skip
        // both the sort and the full index rebuild.
        let affectsPresentationIndex = advancesCurrentState
            || createdSession
            || completedByParentRule
            || event.parentSessionId != nil
            || event.task != nil
        if affectsPresentationIndex {
            sessions.sort(by: Self.orderSessions)
            rebuildLookups()
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
        normalizeRestoredSessions()
        // Restoring from disk has no live event stream; rebuild the temporary
        // attention surface from any session that is still waiting for input.
        commitSessionChanges(orderSessions: true, attentionRefresh: .always)
    }

    public func reconcilePendingReplies(isLive: (UUID) -> Bool) {
        for index in sessions.indices {
            sessions[index].retainPendingReplies(where: isLive)
        }
        commitSessionChanges(orderSessions: false, attentionRefresh: .ifMissing)
    }

    /// Reconciles workflow metadata discovered from provider-owned storage
    /// without treating app startup as new agent activity.
    public func reconcileRestoredWorkflow(_ event: AgentEvent) {
        guard event.protocolVersion == 1, event.provider == .grok else { return }
        // Missing rows are leftover on-disk evidence, not a new live agent.
        // Creating AgentSession(event:) here would adopt the restore event's
        // running state and skip cold-start unknown/cascade rules.
        guard let index = sessionsByID[event.sessionId] else { return }
        guard sessions[index].reconcileRestoredWorkflow(event) else { return }
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
    /// Waiting sessions with a live or unknown origin are preserved: the
    /// provider may still be blocked on an approval that will not emit another
    /// hook until the user answers. When `origin.processIdentifier` is present
    /// and the process is gone or its start identity changed, every active state
    /// completes immediately. A waiter with a live PID and no recorded start
    /// time stays waiting.
    /// Remaining non-waiting actives become `.unknown` (reconnecting) instead
    /// of inventing a completion; a later live event or grace-period expiry
    /// resolves them.
    public func reconcileUnverifiedActiveSessions(
        processAlive: (Int32) -> Bool = { pid in
            guard pid > 0 else { return false }
            return kill(pid, 0) == 0
        },
        processStartedAt: ((Int32) -> Date?)? = nil
    ) {
        let resolveProcessStart = processStartedAt ?? { pid in
            AgentProcessIdentity.startedAt(for: pid)
        }
        var changed = false
        for index in sessions.indices where sessions[index].isActive {
            if sessions[index].state == .unknown {
                continue
            }
            if let origin = sessions[index].origin,
               origin.processIdentifier != nil,
               !origin.matchesRunningProcess(
                   processAlive: processAlive,
                   currentStartedAt: resolveProcessStart
               )
            {
                let completedAt = sessions[index].updatedAt
                let parentID = sessions[index].id
                sessions[index].complete(as: .completed, at: completedAt)
                // Match ingest: active/waiting children under a terminal parent
                // must not linger as attention pins after the origin dies.
                completeActiveDescendants(of: parentID, as: .completed, at: completedAt)
                changed = true
                continue
            }
            if sessions[index].state == .waitingForUser {
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
            let parentID = sessions[index].id
            let completedAt = sessions[index].updatedAt
            sessions[index].complete(as: .completed, at: completedAt)
            // Match ingest and dead-PID reconcile: waiting children under a
            // terminal parent must not linger as attention pins.
            completeActiveDescendants(of: parentID, as: .completed, at: completedAt)
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
        guard let index = sessionsByID[sessionId] else { return }
        guard sessions[index].applyRestoredLifecycle(
            state: state,
            activity: activity,
            at: timestamp
        ) else { return }
        if state == .completed || state == .failed {
            completeActiveDescendants(of: sessionId, as: state, at: timestamp)
        }
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
    ///
    /// Scans `sessions` directly instead of reading the presentation index so
    /// hot-path ingests do not force a full graph rebuild just to re-rank
    /// attention. Ordering matches SessionIndex.waitingSessions exactly.
    private func latestWaitingAttentionEvent() -> AgentEvent? {
        var newest: AgentSession?
        for session in sessions where session.state == .waitingForUser {
            if let current = newest {
                if session.updatedAt > current.updatedAt
                    || (session.updatedAt == current.updatedAt && session.id < current.id)
                {
                    newest = session
                }
            } else {
                newest = session
            }
        }
        return newest.map(attentionEvent(for:))
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
        guard let sessionIndex = sessionsByID[sessionID],
              sessions[sessionIndex].isActive,
              let parentID = sessions[sessionIndex].parentSessionId,
              let parentIndex = sessionsByID[parentID]
        else { return false }
        let parent = sessions[parentIndex]
        guard parent.state == .completed || parent.state == .failed else { return false }
        sessions[sessionIndex].complete(as: parent.state, at: max(parent.updatedAt, timestamp))
        return true
    }

    /// Restore normalization: drop orphaned Grok SessionStart rows, prefix
    /// every session and parent, then keep the newest row per identity.
    /// Idempotent. Runs on init and every replaceSessions restore boundary.
    private func normalizeRestoredSessions() {
        sessions.removeAll(where: Self.isOrphanedGrokStart)
        for index in sessions.indices {
            namespaceSessionIdentity(&sessions[index])
        }

        var newestByIdentity: [String: AgentSession] = [:]
        for session in sessions {
            let key = session.provider.rawValue + "\0" + session.id
            if let existing = newestByIdentity[key], existing.updatedAt >= session.updatedAt {
                continue
            }
            newestByIdentity[key] = session
        }
        sessions = Array(newestByIdentity.values)
        for index in sessions.indices {
            sessions[index].pendingReply = nil
            sessions[index].pendingReplies.removeAll()
        }
    }

    private func namespaceSessionIdentity(_ session: inout AgentSession) {
        let originalID = session.id
        let canonicalID = session.provider.namespacedSessionID(originalID)
        if session.id != canonicalID {
            session.id = canonicalID
        }
        if let parentID = session.parentSessionId {
            session.parentSessionId = session.provider.namespacedSessionID(parentID)
        }
        for eventIndex in session.recentEvents.indices {
            var event = session.recentEvents[eventIndex]
            event.sessionId = session.provider.namespacedSessionID(event.sessionId)
            if let parentID = event.parentSessionId {
                event.parentSessionId = session.provider.namespacedSessionID(parentID)
            }
            session.recentEvents[eventIndex] = event
        }
        if attentionEvent?.sessionId == originalID, attentionEvent?.provider == session.provider {
            attentionEvent?.sessionId = canonicalID
        }
    }

    private func rebuildLookups() {
        sessionsByID.removeAll(keepingCapacity: true)
        for (offset, session) in sessions.enumerated() {
            sessionsByID[session.id] = offset
        }
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
        rebuildLookups()
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

    /// Pure ordering used as a `sort(by:)` predicate. Must stay `nonisolated`
    /// so Swift 6.0 can pass it to synchronous collection APIs from `@MainActor`.
    nonisolated private static func orderSessions(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        return lhs.updatedAt > rhs.updatedAt
    }

    /// Removes rows persisted by older builds when Grok initialized a command
    /// but never began an agent turn. Real Grok sessions have at least one
    /// prompt, tool, notification, or terminal event after SessionStart.
    /// `nonisolated` so Swift 6.0 can pass it to `removeAll(where:)`.
    nonisolated private static func isOrphanedGrokStart(_ session: AgentSession) -> Bool {
        guard session.provider == .grok,
              session.state == .starting,
              !session.recentEvents.isEmpty
        else { return false }

        return session.recentEvents.allSatisfy { event in
            guard event.type == .started,
                  let hookEvent = event.metadata?["hookEvent"]
            else { return false }
            return HookEventName(rawEventName: hookEvent) == .sessionStart
        }
    }
}
