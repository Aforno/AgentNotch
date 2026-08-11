import Foundation

/// Immutable projection of the session graph used by the activity service.
/// Keeping graph construction here prevents event reduction from also owning
/// hierarchy traversal and notch presentation policy.
struct SessionIndex {
    struct GroupAggregate {
        let needsAttention: Bool
        let isActive: Bool
        let updatedAt: Date
    }

    private struct SessionGroups {
        let hierarchicalSessions: [AgentSession]
        let roots: [AgentSession]
        let membersByRootID: [String: [AgentSession]]
        let rootIDBySessionID: [String: String]
        let aggregates: [String: GroupAggregate]
    }

    private struct GroupBuilder {
        var hierarchicalSessions: [AgentSession] = []
        var roots: [AgentSession] = []
        var membersByRootID: [String: [AgentSession]] = [:]
        var rootIDBySessionID: [String: String] = [:]
        var aggregates: [String: GroupAggregate] = [:]
        var visited: Set<String> = []

        init(capacity: Int) {
            hierarchicalSessions.reserveCapacity(capacity)
        }

        mutating func append(root: AgentSession, members: [AgentSession]) {
            let unvisited = members.filter { visited.insert($0.id).inserted }
            guard !unvisited.isEmpty else { return }

            roots.append(root)
            membersByRootID[root.id] = unvisited
            for session in unvisited {
                rootIDBySessionID[session.id] = root.id
            }
            aggregates[root.id] = SessionIndex.aggregate(unvisited, fallback: root)
            hierarchicalSessions.append(contentsOf: unvisited)
        }

        var result: SessionGroups {
            SessionGroups(
                hierarchicalSessions: hierarchicalSessions,
                roots: roots,
                membersByRootID: membersByRootID,
                rootIDBySessionID: rootIDBySessionID,
                aggregates: aggregates
            )
        }
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
        let sessionsByID = Self.indexByID(sessions)
        let childrenByParentID = Self.indexChildren(sessions)
        let groups = Self.makeGroups(
            sessions: sessions,
            sessionsByID: sessionsByID,
            childrenByParentID: childrenByParentID
        )
        let activeSessions = sessions.filter(\.isActive)

        self.sessionsByID = sessionsByID
        self.childrenByParentID = childrenByParentID
        hierarchicalSessions = groups.hierarchicalSessions
        groupRoots = groups.roots
        groupMembersByRootID = groups.membersByRootID
        groupRootIDBySessionID = groups.rootIDBySessionID
        groupAggregates = groups.aggregates
        self.activeSessions = activeSessions
        activeProviders = Self.uniqueProviders(in: activeSessions)
        attentionSessions = Self.waitingSessions(in: sessions)
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
        let listSessions = latestGroupRoots()
        let attentionSession = attentionEvent
            .flatMap { sessionsByID[$0.sessionId] }
            ?? attentionSessions.first

        return NotchActivitySnapshot(
            activeSessions: activeSessions,
            activeProviders: activeProviders,
            activeGroupCount: activeGroupCount,
            attentionSessions: attentionSessions,
            attentionSession: attentionSession,
            listSessions: listSessions,
            relatedSessions: relatedSessions(
                for: listSessions,
                includingGroupOf: attentionSession
            )
        )
    }

    private var activeGroupCount: Int {
        groupRoots.reduce(into: 0) { count, root in
            if groupAggregates[root.id]?.isActive == true {
                count += 1
            }
        }
    }

    private func latestGroupRoots() -> [AgentSession] {
        Array(
            groupRoots
                .sorted { lhs, rhs in
                    let lhsUpdatedAt = groupAggregates[lhs.id]?.updatedAt ?? lhs.updatedAt
                    let rhsUpdatedAt = groupAggregates[rhs.id]?.updatedAt ?? rhs.updatedAt
                    if lhsUpdatedAt != rhsUpdatedAt { return lhsUpdatedAt > rhsUpdatedAt }
                    return lhs.id < rhs.id
                }
                .prefix(3)
        )
    }

    private func relatedSessions(
        for roots: [AgentSession],
        includingGroupOf attentionSession: AgentSession?
    ) -> [AgentSession] {
        var relatedSessions: [AgentSession] = []
        var relatedIDs: Set<String> = []

        func appendGroup(rootID: String, fallback: AgentSession) {
            for session in groupMembersByRootID[rootID] ?? [fallback]
                where relatedIDs.insert(session.id).inserted
            {
                relatedSessions.append(session)
            }
        }

        for root in roots {
            appendGroup(rootID: root.id, fallback: root)
        }
        if let attentionSession,
           let rootID = groupRootIDBySessionID[attentionSession.id]
        {
            appendGroup(rootID: rootID, fallback: attentionSession)
        }
        return relatedSessions
    }

    private static func indexByID(_ sessions: [AgentSession]) -> [String: AgentSession] {
        var result: [String: AgentSession] = [:]
        result.reserveCapacity(sessions.count)
        for session in sessions {
            result[session.id] = session
        }
        return result
    }

    private static func indexChildren(_ sessions: [AgentSession]) -> [String: [AgentSession]] {
        var result: [String: [AgentSession]] = [:]
        for session in sessions {
            guard let parentID = session.parentSessionId else { continue }
            result[parentID, default: []].append(session)
        }
        for parentID in result.keys {
            result[parentID]?.sort(by: orderSessions)
        }
        return result
    }

    private static func makeGroups(
        sessions: [AgentSession],
        sessionsByID: [String: AgentSession],
        childrenByParentID: [String: [AgentSession]]
    ) -> SessionGroups {
        let naturalRoots = sessions.filter { session in
            guard let parentID = session.parentSessionId else { return true }
            return sessionsByID[parentID] == nil
        }
        let membersByRootID = Dictionary(uniqueKeysWithValues: naturalRoots.map { root in
            (root.id, hierarchy(from: root, childrenByParentID: childrenByParentID))
        })
        let aggregates = Dictionary(uniqueKeysWithValues: naturalRoots.map { root in
            let members = membersByRootID[root.id] ?? [root]
            return (root.id, aggregate(members, fallback: root))
        })
        let orderedRoots = naturalRoots.sorted { lhs, rhs in
            orderGroups(lhs, rhs, aggregates: aggregates)
        }

        var builder = GroupBuilder(capacity: sessions.count)
        for root in orderedRoots {
            builder.append(root: root, members: membersByRootID[root.id] ?? [root])
        }

        // Malformed external input can contain cycles with no natural root. Use
        // the first remaining row as a deterministic presentation root and walk
        // the component once, preserving visibility without repeated scans.
        for session in sessions where !builder.visited.contains(session.id) {
            builder.append(
                root: session,
                members: hierarchy(from: session, childrenByParentID: childrenByParentID)
            )
        }
        return builder.result
    }

    private static func uniqueProviders(in sessions: [AgentSession]) -> [AgentProvider] {
        var seen = Set<AgentProvider>()
        return sessions
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                if lhs.provider != rhs.provider { return lhs.provider.rawValue < rhs.provider.rawValue }
                return lhs.id < rhs.id
            }
            .compactMap { session in
                seen.insert(session.provider).inserted ? session.provider : nil
            }
    }

    private static func waitingSessions(in sessions: [AgentSession]) -> [AgentSession] {
        sessions
            .filter { $0.state == .waitingForUser }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id < rhs.id
            }
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
            ?? aggregate([lhs], fallback: lhs)
        let rhsAggregate = aggregates[rhs.id]
            ?? aggregate([rhs], fallback: rhs)
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
