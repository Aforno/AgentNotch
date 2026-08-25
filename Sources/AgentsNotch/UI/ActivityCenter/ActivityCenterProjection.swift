import AgentsNotchCore
import Foundation
import Observation

enum ActivityStatusFilter: String, CaseIterable, Identifiable {
    case all, active, attention, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .attention: "Attention"
        case .completed: "Completed"
        }
    }
}

enum ActivityGroupingMode: String, CaseIterable, Identifiable {
    case grouped, allSessions
    var id: String { rawValue }
    var title: String { self == .grouped ? "Grouped" : "All sessions" }
}

enum ActivityDateFilter: String, CaseIterable, Identifiable {
    case all, today, sevenDays, thirtyDays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Any time"
        case .today: "Today"
        case .sevenDays: "Last 7 days"
        case .thirtyDays: "Last 30 days"
        }
    }

    func includes(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: true
        case .today: date >= calendar.startOfDay(for: now)
        case .sevenDays: date >= calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .thirtyDays: date >= calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        }
    }
}

struct ActivityProjectOption: Identifiable, Equatable { let id: String; let title: String }
struct ActivitySessionGroup: Identifiable, Equatable {
    let root: AgentSession
    let children: [AgentSession]
    let latestUpdatedAt: Date
    var id: String { root.id }
}
struct ActivityProjectSection: Identifiable, Equatable {
    let id: String
    let title: String
    let groups: [ActivitySessionGroup]
    let latestUpdatedAt: Date
    var sessionCount: Int { groups.reduce(0) { $0 + 1 + $1.children.count } }
}

@Observable
@MainActor
final class ActivityCenterProjection {
    private struct State: Equatable {
        let filteredSessions: [AgentSession]
        let filteredSessionIDs: Set<String>
        let availableProviders: [AgentProvider]
        let availableProjects: [ActivityProjectOption]
        let projectGroups: [ActivityProjectSection]
        let sessionCount: Int
        let hasRecentSessions: Bool
        static let empty = State(filteredSessions: [], filteredSessionIDs: [], availableProviders: [], availableProjects: [], projectGroups: [], sessionCount: 0, hasRecentSessions: false)
    }

    private var state = State.empty
    @ObservationIgnored private var sessionsByID: [String: AgentSession] = [:]
    @ObservationIgnored private var childrenByParentID: [String: [AgentSession]] = [:]
    var filteredSessions: [AgentSession] { state.filteredSessions }
    var filteredSessionIDs: Set<String> { state.filteredSessionIDs }
    var availableProviders: [AgentProvider] { state.availableProviders }
    var availableProjects: [ActivityProjectOption] { state.availableProjects }
    var projectGroups: [ActivityProjectSection] { state.projectGroups }
    var sessionCount: Int { state.sessionCount }
    var hasRecentSessions: Bool { state.hasRecentSessions }

    func session(id: String) -> AgentSession? { sessionsByID[id] }
    func parent(of session: AgentSession) -> AgentSession? { session.parentSessionId.flatMap { sessionsByID[$0] } }
    func children(of sessionID: String) -> [AgentSession] { childrenByParentID[sessionID] ?? [] }
    func groupID(containing sessionID: String) -> String? {
        guard sessionsByID[sessionID] != nil else { return nil }
        return Self.rootID(for: sessionID, sessionsByID: sessionsByID)
    }

    func update(
        sessions: [AgentSession],
        searchText: String,
        providerFilter: String,
        statusFilter: ActivityStatusFilter,
        projectFilter: String = "all",
        dateFilter: ActivityDateFilter = .all,
        now: Date = Date()
    ) {
        let sessions = sessions.filter {
            !AgentTaskTitle.isInternalHelper($0)
        }
        var sessionsByID: [String: AgentSession] = [:]
        var childrenByParentID: [String: [AgentSession]] = [:]
        var providers = Set<AgentProvider>()
        for session in sessions {
            sessionsByID[session.id] = session
            providers.insert(AgentProvider(rawValue: Self.canonicalProviderRawValue(session.provider.rawValue)))
            if let parentID = session.parentSessionId { childrenByParentID[parentID, default: []].append(session) }
        }
        for parentID in childrenByParentID.keys { childrenByParentID[parentID]?.sort(by: Self.orderSessions) }
        self.sessionsByID = sessionsByID
        self.childrenByParentID = childrenByParentID

        let projectKeyBySessionID = Dictionary(uniqueKeysWithValues: sessions.map { session in
            let root = sessionsByID[Self.rootID(for: session.id, sessionsByID: sessionsByID)] ?? session
            return (session.id, root.workingDirectory ?? session.workingDirectory ?? "provider:\(root.provider.rawValue)")
        })
        let projectTitles = Dictionary(grouping: sessions, by: { projectKeyBySessionID[$0.id] ?? "provider:\($0.provider.rawValue)" })
            .mapValues { candidates in
                candidates.compactMap(\.workingDirectory).first.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? candidates.first?.provider.displayName ?? "Unknown project"
            }
        let projectOptions: [ActivityProjectOption] = projectTitles.map {
            ActivityProjectOption(id: $0.key, title: $0.value)
        }
        let projectTitleCounts = Dictionary(grouping: projectOptions) { $0.title.lowercased() }
            .mapValues(\.count)
        let labeledProjects = projectOptions.map { project in
            guard projectTitleCounts[project.title.lowercased(), default: 0] > 1 else { return project }
            let location = (project.id as NSString).abbreviatingWithTildeInPath
            return ActivityProjectOption(id: project.id, title: "\(project.title) — \(location)")
        }
        let projectLabelGroups = Dictionary(grouping: labeledProjects) { $0.title.lowercased() }
        let availableProjects = labeledProjects.map { project in
            let matches = projectLabelGroups[project.title.lowercased(), default: []].sorted { $0.id < $1.id }
            guard matches.count > 1, let index = matches.firstIndex(where: { $0.id == project.id }) else { return project }
            return ActivityProjectOption(id: project.id, title: "\(project.title) (\(index + 1))")
        }.sorted { lhs, rhs in
            if lhs.title != rhs.title {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = sessions.filter { session in
            guard providerFilter == "all"
                    || Self.canonicalProviderRawValue(session.provider.rawValue)
                        == Self.canonicalProviderRawValue(providerFilter),
                  projectFilter == "all" || projectKeyBySessionID[session.id] == projectFilter,
                  dateFilter.includes(session.updatedAt, now: now)
            else { return false }
            let statusMatches = switch statusFilter {
            case .all: true
            case .active: session.isActive
            case .attention: session.state == .waitingForUser
            case .completed: !session.isActive
            }
            return statusMatches && (query.isEmpty || Self.searchText(for: session).localizedCaseInsensitiveContains(query))
        }.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }

        let projectGroups = Self.makeProjectGroups(matchingSessions: filtered, sessionsByID: sessionsByID, projectKeyBySessionID: projectKeyBySessionID, projectTitles: projectTitles)
        let contextualRootIDs = Set(projectGroups.flatMap { $0.groups.map(\.root.id) })
        let next = State(
            filteredSessions: filtered,
            filteredSessionIDs: Set(filtered.map(\.id)).union(contextualRootIDs),
            availableProviders: providers.sorted { $0.displayName < $1.displayName },
            availableProjects: availableProjects,
            projectGroups: projectGroups,
            sessionCount: sessions.count,
            hasRecentSessions: sessions.contains { !$0.isActive }
        )
        if next != state { state = next }
    }

    nonisolated private static func orderSessions(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        return lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.id < rhs.id
    }

    private static func canonicalProviderRawValue(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "claude": AgentProvider.claudeCode.rawValue
        case "gemini": AgentProvider.geminiCLI.rawValue
        default: rawValue.lowercased()
        }
    }

    private static func rootID(for sessionID: String, sessionsByID: [String: AgentSession]) -> String {
        var currentID = sessionID
        var visited: [String] = []
        var visitedSet = Set<String>()
        while visitedSet.insert(currentID).inserted,
              let parentID = sessionsByID[currentID]?.parentSessionId,
              sessionsByID[parentID] != nil
        {
            visited.append(currentID)
            currentID = parentID
        }
        if visitedSet.contains(sessionsByID[currentID]?.parentSessionId ?? "") {
            return (visited + [currentID]).min() ?? sessionID
        }
        return currentID
    }

    private static func makeProjectGroups(
        matchingSessions: [AgentSession],
        sessionsByID: [String: AgentSession],
        projectKeyBySessionID: [String: String],
        projectTitles: [String: String]
    ) -> [ActivityProjectSection] {
        let matchesByRoot = Dictionary(grouping: matchingSessions) { rootID(for: $0.id, sessionsByID: sessionsByID) }
        var groupsByProject: [String: [ActivitySessionGroup]] = [:]
        for (rootID, matches) in matchesByRoot {
            guard let fallback = matches.first else { continue }
            let root = sessionsByID[rootID] ?? fallback
            let children = matches.filter { $0.id != root.id }.sorted(by: orderSessions)
            let latest = ([root] + children).map(\.updatedAt).max() ?? root.updatedAt
            let projectID = projectKeyBySessionID[root.id] ?? projectKeyBySessionID[fallback.id] ?? "provider:\(root.provider.rawValue)"
            groupsByProject[projectID, default: []].append(ActivitySessionGroup(root: root, children: children, latestUpdatedAt: latest))
        }
        return groupsByProject.map { projectID, groups in
            let sorted = groups.sorted { $0.latestUpdatedAt != $1.latestUpdatedAt ? $0.latestUpdatedAt > $1.latestUpdatedAt : $0.id < $1.id }
            return ActivityProjectSection(id: projectID, title: projectTitles[projectID] ?? "Unknown project", groups: sorted, latestUpdatedAt: sorted.map(\.latestUpdatedAt).max() ?? .distantPast)
        }.sorted { $0.latestUpdatedAt != $1.latestUpdatedAt ? $0.latestUpdatedAt > $1.latestUpdatedAt : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func searchText(for session: AgentSession) -> String {
        var values = [session.task, session.currentActivity, session.workingDirectory ?? "", session.provider.displayName, session.agentRole ?? ""]
        values.append(contentsOf: session.recentFiles)
        values.append(contentsOf: session.recentEvents.map { [$0.activity, $0.file, $0.resolvedState.displayName].compactMap { $0 }.joined(separator: " ") })
        if let plan = session.plan {
            values += [plan.title ?? "", plan.explanation ?? ""]
            values.append(contentsOf: plan.steps.flatMap { [$0.title, $0.status.displayName] })
        }
        for workflow in session.workflows {
            values += [workflow.title, workflow.status.displayName]
            values.append(contentsOf: workflow.steps.flatMap { [$0.title, $0.status.displayName] })
        }
        return values.joined(separator: " ")
    }
}
