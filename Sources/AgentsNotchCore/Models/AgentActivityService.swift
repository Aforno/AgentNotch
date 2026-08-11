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

    public func ingest(_ event: AgentEvent) {
        guard event.protocolVersion == 1 else { return }
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
        rebuildIndex()

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
        rebuildIndex()
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
    }

    public func replaceSessions(_ sessions: [AgentSession]) {
        self.sessions = sessions
            .filter { !Self.isOrphanedGrokStart($0) }
        normalizeRestoredIdentities()
        self.sessions.sort(by: Self.orderSessions)
        rebuildIndex()
        // Restoring from disk has no live event stream; rebuild the temporary
        // attention surface from any session that is still waiting for input.
        attentionEvent = latestWaitingAttentionEvent()
        publishNotchSnapshot()
        notifySessionsChanged()
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
        sessions.sort(by: Self.orderSessions)
        rebuildIndex()
        publishNotchSnapshot()
        notifySessionsChanged()
    }

    public func removeSession(id: String) {
        let previousCount = sessions.count
        sessions.removeAll { $0.id == id }
        guard sessions.count != previousCount else { return }
        rebuildIndex()
        if attentionEvent?.sessionId == id {
            attentionEvent = latestWaitingAttentionEvent()
        }
        publishNotchSnapshot()
        notifySessionsChanged()
    }

    public func removeSessions(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let previousCount = sessions.count
        sessions.removeAll { ids.contains($0.id) }
        guard sessions.count != previousCount else { return }
        rebuildIndex()
        if let attentionEvent, ids.contains(attentionEvent.sessionId) {
            self.attentionEvent = latestWaitingAttentionEvent()
        }
        publishNotchSnapshot()
        notifySessionsChanged()
    }

    public func clearRecent() {
        let previousCount = sessions.count
        sessions.removeAll { !$0.isActive }
        guard sessions.count != previousCount else { return }
        rebuildIndex()
        if let attentionEvent, index.sessionsByID[attentionEvent.sessionId] == nil {
            self.attentionEvent = latestWaitingAttentionEvent()
        }
        publishNotchSnapshot()
        notifySessionsChanged()
    }

    public func pruneCompleted(olderThan age: TimeInterval, now: Date = Date()) {
        let previousCount = sessions.count
        sessions.removeAll { session in
            guard let completedAt = session.completedAt else { return false }
            return now.timeIntervalSince(completedAt) > age
        }
        guard sessions.count != previousCount else { return }
        rebuildIndex()
        if let attentionEvent, index.sessionsByID[attentionEvent.sessionId] == nil {
            self.attentionEvent = latestWaitingAttentionEvent()
        }
        publishNotchSnapshot()
        notifySessionsChanged()
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
        sessions.sort(by: Self.orderSessions)
        rebuildIndex()
        attentionEvent = latestWaitingAttentionEvent()
        publishNotchSnapshot()
        notifySessionsChanged()
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
        sessions.sort(by: Self.orderSessions)
        rebuildIndex()
        attentionEvent = latestWaitingAttentionEvent()
        publishNotchSnapshot()
        notifySessionsChanged()
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
        sessions.sort(by: Self.orderSessions)
        rebuildIndex()
        attentionEvent = latestWaitingAttentionEvent()
        publishNotchSnapshot()
        notifySessionsChanged()
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

    private func completeActiveDescendants(
        of parentID: String,
        as state: AgentState,
        at timestamp: Date
    ) {
        let descendantIDs = index.descendantIDs(of: parentID)
        guard !descendantIDs.isEmpty else { return }
        for index in sessions.indices
            where descendantIDs.contains(sessions[index].id) && sessions[index].isActive
        {
            sessions[index].complete(as: state, at: timestamp)
        }
    }

    private func completeSessionIfParentIsTerminal(_ sessionID: String, at timestamp: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let parentID = sessions[index].parentSessionId,
              let parent = sessions.first(where: { $0.id == parentID }),
              parent.state == .completed || parent.state == .failed
        else { return }
        sessions[index].complete(as: parent.state, at: max(parent.updatedAt, timestamp))
    }

    private func canonicalizedIdentity(for event: AgentEvent) -> AgentEvent {
        var event = event
        let prefix = "\(event.provider.rawValue):"

        // After a prior cross-provider collision, rows are stored as provider:id.
        // Later events still carrying the bare id must resolve to that row
        // instead of creating a duplicate unprefixed session.
        if !event.sessionId.hasPrefix(prefix) {
            let canonicalID = prefix + event.sessionId
            if sessions.contains(where: { $0.id == canonicalID && $0.provider == event.provider }) {
                event.sessionId = canonicalID
                if let parentID = event.parentSessionId, !parentID.hasPrefix(prefix),
                   sessions.contains(where: {
                       $0.id == prefix + parentID && $0.provider == event.provider
                   })
                {
                    event.parentSessionId = prefix + parentID
                }
                return event
            }
        }

        let collidingIndices = sessions.indices.filter {
            sessions[$0].id == event.sessionId && sessions[$0].provider != event.provider
        }
        guard !collidingIndices.isEmpty else {
            return event
        }
        let originalID = event.sessionId
        for index in collidingIndices {
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

    private func rebuildIndex() {
        index = SessionIndex(sessions: sessions)
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

private struct SessionIndex {
    struct GroupAggregate {
        let needsAttention: Bool
        let isActive: Bool
        let updatedAt: Date
    }

    let sessionsByID: [String: AgentSession]
    let childrenByParentID: [String: [AgentSession]]
    let hierarchicalSessions: [AgentSession]
    let activeSessions: [AgentSession]
    let activeProviders: [AgentProvider]
    let attentionSessions: [AgentSession]
    let groupRoots: [AgentSession]
    let groupMembersByRootID: [String: [AgentSession]]
    let groupRootIDBySessionID: [String: String]
    let groupAggregates: [String: GroupAggregate]

    static let empty = SessionIndex(sessions: [])

    init(sessions: [AgentSession]) {
        var sessionsByID: [String: AgentSession] = [:]
        sessionsByID.reserveCapacity(sessions.count)
        for session in sessions {
            sessionsByID[session.id] = session
        }
        self.sessionsByID = sessionsByID

        var childrenByParentID: [String: [AgentSession]] = [:]
        for session in sessions {
            guard let parentID = session.parentSessionId else { continue }
            childrenByParentID[parentID, default: []].append(session)
        }
        for parentID in childrenByParentID.keys {
            childrenByParentID[parentID]?.sort(by: Self.orderSessions)
        }
        self.childrenByParentID = childrenByParentID

        let naturalRoots = sessions.filter { session in
            guard let parentID = session.parentSessionId else { return true }
            return sessionsByID[parentID] == nil
        }

        var membersByCandidateRoot: [String: [AgentSession]] = [:]
        var aggregatesByCandidateRoot: [String: GroupAggregate] = [:]
        for root in naturalRoots {
            let members = Self.hierarchy(
                from: root,
                childrenByParentID: childrenByParentID
            )
            membersByCandidateRoot[root.id] = members
            aggregatesByCandidateRoot[root.id] = Self.aggregate(members, fallback: root)
        }

        let orderedNaturalRoots = naturalRoots.sorted { lhs, rhs in
            Self.orderGroups(
                lhs,
                rhs,
                aggregates: aggregatesByCandidateRoot
            )
        }

        var hierarchicalSessions: [AgentSession] = []
        hierarchicalSessions.reserveCapacity(sessions.count)
        var groupRoots: [AgentSession] = []
        var groupMembersByRootID: [String: [AgentSession]] = [:]
        var groupRootIDBySessionID: [String: String] = [:]
        var groupAggregates: [String: GroupAggregate] = [:]
        var visited: Set<String> = []

        func appendGroup(root: AgentSession, members: [AgentSession]) {
            let unvisited = members.filter { visited.insert($0.id).inserted }
            guard !unvisited.isEmpty else { return }
            groupRoots.append(root)
            groupMembersByRootID[root.id] = unvisited
            for session in unvisited {
                groupRootIDBySessionID[session.id] = root.id
            }
            groupAggregates[root.id] = Self.aggregate(unvisited, fallback: root)
            hierarchicalSessions.append(contentsOf: unvisited)
        }

        for root in orderedNaturalRoots {
            appendGroup(root: root, members: membersByCandidateRoot[root.id] ?? [root])
        }

        // Malformed external input can contain cycles with no natural root. Use
        // the first remaining row as a deterministic presentation root and walk
        // the component once, preserving visibility without repeated scans.
        for session in sessions where !visited.contains(session.id) {
            appendGroup(
                root: session,
                members: Self.hierarchy(
                    from: session,
                    childrenByParentID: childrenByParentID
                )
            )
        }

        self.hierarchicalSessions = hierarchicalSessions
        self.groupRoots = groupRoots
        self.groupMembersByRootID = groupMembersByRootID
        self.groupRootIDBySessionID = groupRootIDBySessionID
        self.groupAggregates = groupAggregates

        activeSessions = sessions.filter(\.isActive)
        var seenProviders = Set<AgentProvider>()
        activeProviders = activeSessions
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                if lhs.provider != rhs.provider { return lhs.provider.rawValue < rhs.provider.rawValue }
                return lhs.id < rhs.id
            }
            .compactMap { session in
                seenProviders.insert(session.provider).inserted ? session.provider : nil
            }
        attentionSessions = sessions
            .filter { $0.state == .waitingForUser }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id < rhs.id
            }
    }

    func descendantIDs(of sessionID: String) -> Set<String> {
        var result: Set<String> = []
        var pending = [sessionID]
        var visited: Set<String> = [sessionID]
        while let parentID = pending.popLast() {
            for child in childrenByParentID[parentID] ?? []
                where visited.insert(child.id).inserted
            {
                result.insert(child.id)
                pending.append(child.id)
            }
        }
        return result
    }

    func notchSnapshot(attentionEvent: AgentEvent?) -> NotchActivitySnapshot {
        let listSessions = Array(
            groupRoots
                .sorted { lhs, rhs in
                    let lhsUpdatedAt = groupAggregates[lhs.id]?.updatedAt ?? lhs.updatedAt
                    let rhsUpdatedAt = groupAggregates[rhs.id]?.updatedAt ?? rhs.updatedAt
                    if lhsUpdatedAt != rhsUpdatedAt { return lhsUpdatedAt > rhsUpdatedAt }
                    return lhs.id < rhs.id
                }
                .prefix(3)
        )
        var relatedSessions: [AgentSession] = []
        var relatedIDs: Set<String> = []
        for root in listSessions {
            for session in groupMembersByRootID[root.id] ?? [root]
                where relatedIDs.insert(session.id).inserted
            {
                relatedSessions.append(session)
            }
        }
        let attentionSession = attentionEvent
            .flatMap { sessionsByID[$0.sessionId] }
            ?? attentionSessions.first
        if let attentionSession,
           let rootID = groupRootIDBySessionID[attentionSession.id]
        {
            for session in groupMembersByRootID[rootID] ?? [attentionSession]
                where relatedIDs.insert(session.id).inserted
            {
                relatedSessions.append(session)
            }
        }

        return NotchActivitySnapshot(
            activeSessions: activeSessions,
            activeProviders: activeProviders,
            activeGroupCount: groupRoots.reduce(into: 0) { count, root in
                if groupAggregates[root.id]?.isActive == true { count += 1 }
            },
            attentionSessions: attentionSessions,
            attentionSession: attentionSession,
            listSessions: listSessions,
            relatedSessions: relatedSessions
        )
    }

    private static func hierarchy(
        from root: AgentSession,
        childrenByParentID: [String: [AgentSession]]
    ) -> [AgentSession] {
        var result: [AgentSession] = []
        var visited: Set<String> = []

        func append(_ session: AgentSession) {
            guard visited.insert(session.id).inserted else { return }
            result.append(session)
            for child in childrenByParentID[session.id] ?? [] {
                append(child)
            }
        }

        append(root)
        return result
    }

    private static func aggregate(
        _ sessions: [AgentSession],
        fallback: AgentSession
    ) -> GroupAggregate {
        GroupAggregate(
            needsAttention: sessions.contains(where: \.needsAttention),
            isActive: sessions.contains(where: \.isActive),
            updatedAt: sessions.map(\.updatedAt).max() ?? fallback.updatedAt
        )
    }

    private static func orderGroups(
        _ lhs: AgentSession,
        _ rhs: AgentSession,
        aggregates: [String: GroupAggregate]
    ) -> Bool {
        let lhsAggregate = aggregates[lhs.id]
            ?? GroupAggregate(needsAttention: lhs.needsAttention, isActive: lhs.isActive, updatedAt: lhs.updatedAt)
        let rhsAggregate = aggregates[rhs.id]
            ?? GroupAggregate(needsAttention: rhs.needsAttention, isActive: rhs.isActive, updatedAt: rhs.updatedAt)
        if lhsAggregate.needsAttention != rhsAggregate.needsAttention {
            return lhsAggregate.needsAttention
        }
        if lhsAggregate.isActive != rhsAggregate.isActive {
            return lhsAggregate.isActive
        }
        if lhsAggregate.updatedAt != rhsAggregate.updatedAt {
            return lhsAggregate.updatedAt > rhsAggregate.updatedAt
        }
        return lhs.id < rhs.id
    }

    private static func orderSessions(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id < rhs.id
    }
}
