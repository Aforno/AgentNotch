import AgentsNotchCore
import Observation
import SwiftUI

enum ActivityStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case attention
    case completed

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
    case grouped
    case allSessions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .grouped: "Grouped"
        case .allSessions: "All sessions"
        }
    }
}

enum ActivityDateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case sevenDays
    case thirtyDays

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
        case .all:
            true
        case .today:
            date >= calendar.startOfDay(for: now)
        case .sevenDays:
            date >= calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .thirtyDays:
            date >= calendar.date(byAdding: .day, value: -30, to: now) ?? .distantPast
        }
    }
}

struct ActivityCenterView: View {
    let runtime: AppRuntime

    @State private var selection: String?
    @State private var searchText = ""
    @AppStorage("activityProviderFilter") private var providerFilter = "all"
    @AppStorage("activityStatusFilter") private var statusFilterRaw = ActivityStatusFilter.all.rawValue
    @AppStorage("activityProjectFilter") private var projectFilter = "all"
    @AppStorage("activityDateFilter") private var dateFilterRaw = ActivityDateFilter.all.rawValue
    @AppStorage("activityGroupingMode") private var groupingModeRaw = ActivityGroupingMode.grouped.rawValue
    @State private var confirmsClearHistory = false
    @State private var projection = ActivityCenterProjection()
    @State private var searchTask: Task<Void, Never>?
    @State private var expandedGroupIDs = Set<String>()
    @State private var handledSearchRequest: UInt64 = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            NotchHairline()

            HStack(spacing: 0) {
                sidebar
                    .frame(minWidth: 270, idealWidth: 300, maxWidth: 340)

                Rectangle()
                    .fill(NotchWindowPalette.hairline)
                    .frame(width: 0.6)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(NotchWindowPalette.primaryText)
        .frame(minWidth: 760, minHeight: 500)
        .deepBlackWindowSurface()
        .confirmationDialog(
            "Clear completed session history?",
            isPresented: $confirmsClearHistory
        ) {
            Button("Clear History", role: .destructive) { runtime.clearHistory() }
        } message: {
            Text("Active and waiting sessions will be kept.")
        }
        .onAppear {
            refreshProjection()
            synchronizeSelection()
            handleSearchRequest()
        }
        .onDisappear { searchTask?.cancel() }
        .onChange(of: runtime.activity.historyRevision) { _, _ in
            refreshProjection()
            synchronizeSelection()
        }
        .onChange(of: providerFilter) { _, _ in
            refreshProjection()
            synchronizeSelection()
        }
        .onChange(of: statusFilterRaw) { _, _ in
            refreshProjection()
            synchronizeSelection()
        }
        .onChange(of: projectFilter) { _, _ in
            refreshProjection()
            synchronizeSelection()
        }
        .onChange(of: dateFilterRaw) { _, _ in
            refreshProjection()
            synchronizeSelection()
        }
        .onChange(of: groupingModeRaw) { _, _ in synchronizeSelection() }
        .onChange(of: searchText) { _, _ in scheduleSearchRefresh() }
        .onChange(of: projection.filteredSessionIDs) { _, _ in synchronizeSelection() }
        .onChange(of: runtime.requestedSessionID) { _, requested in
            guard let requested else { return }
            revealAndSelect(requested)
            runtime.consumeRequestedSession(requested)
        }
        .onChange(of: runtime.activitySearchRequest) { _, _ in
            handleSearchRequest()
        }
        .onMoveCommand(perform: moveSelection)
        .onDeleteCommand(perform: removeSelectedSession)
        .onKeyPress(.return) {
            guard !isSearchFocused else { return .ignored }
            openSelectedSession()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Activity")
                    .font(NotchWindowFont.display)
                    .foregroundStyle(.white.opacity(0.92))
                Text(sessionCountSummary)
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }

            Spacer()

            ActivityMetric(
                title: "Active",
                value: runtime.activity.notchSnapshot.activeSessions.count,
                color: .blue
            )
            ActivityMetric(
                title: "Attention",
                value: runtime.activity.notchSnapshot.attentionCount,
                color: .orange
            )

            Menu {
                Button("Clear Completed History", role: .destructive) {
                    confirmsClearHistory = true
                }
                .disabled(!projection.hasRecentSessions)
            } label: {
                NotchIconControlLabel(systemName: "ellipsis")
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Activity options")
        }
        .padding(.horizontal, NotchWindowMetrics.contentInset)
        .padding(.vertical, 14)
        .background(NotchWindowPalette.background)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            filterControls

            NotchHairline()

            if projection.filteredSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                    Text("No matching sessions")
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            if groupingMode == .grouped {
                                ForEach(projection.projectGroups) { project in
                                    projectSection(project)
                                }
                            } else {
                                ForEach(projection.filteredSessions) { session in
                                    sessionButton(session)
                                        .id(session.id)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.visible)
                    .onChange(of: selection) { _, selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(NotchWindowPalette.background)
    }

    private var filterControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchWindowPalette.tertiaryText)

                TextField("Search sessions", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(NotchWindowFont.bodyEmphasis)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                NotchWindowPalette.raised,
                in: RoundedRectangle(cornerRadius: NotchWindowMetrics.controlRadius, style: .continuous)
            )

            HStack(spacing: 7) {
                NotchMenuPicker(
                    selection: $providerFilter,
                    options: [(value: "all", title: "All providers")] + projection.availableProviders.map {
                        (value: $0.rawValue, title: $0.displayName)
                    },
                    accessibilityLabel: "Provider",
                    fillsAvailableWidth: true
                )
                .frame(maxWidth: .infinity)

                NotchMenuPicker(
                    selection: statusFilterBinding,
                    options: ActivityStatusFilter.allCases.map {
                        (value: $0, title: $0.title)
                    },
                    accessibilityLabel: "Status",
                    fillsAvailableWidth: true
                )
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 7) {
                NotchMenuPicker(
                    selection: $projectFilter,
                    options: [(value: "all", title: "All projects")] + projection.availableProjects.map {
                        (value: $0.id, title: $0.title)
                    },
                    accessibilityLabel: "Project",
                    fillsAvailableWidth: true
                )
                .frame(maxWidth: .infinity)

                NotchMenuPicker(
                    selection: dateFilterBinding,
                    options: ActivityDateFilter.allCases.map {
                        (value: $0, title: $0.title)
                    },
                    accessibilityLabel: "Date",
                    fillsAvailableWidth: true
                )
                .frame(maxWidth: .infinity)
            }

            NotchMenuPicker(
                selection: groupingModeBinding,
                options: ActivityGroupingMode.allCases.map {
                    (value: $0, title: $0.title)
                },
                accessibilityLabel: "Session grouping",
                fillsAvailableWidth: true
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func projectSection(_ project: ActivityProjectSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .medium))
                Text(project.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(project.sessionCount)")
                    .monospacedDigit()
            }
            .font(NotchWindowFont.footnote)
            .foregroundStyle(NotchWindowPalette.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ForEach(project.groups) { group in
                sessionGroup(group)
            }
        }
    }

    private func sessionGroup(_ group: ActivitySessionGroup) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if group.children.isEmpty {
                    Color.clear.frame(width: 20, height: 28)
                } else {
                    Button {
                        toggleGroup(group.id)
                    } label: {
                        Image(systemName: expandedGroupIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(NotchWindowPalette.tertiaryText)
                            .frame(width: 20, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expandedGroupIDs.contains(group.id) ? "Collapse agent group" : "Expand agent group")
                    .accessibilityLabel(expandedGroupIDs.contains(group.id) ? "Collapse agent group" : "Expand agent group")
                }

                sessionButton(group.root)
                    .id(group.root.id)
            }

            if expandedGroupIDs.contains(group.id) {
                ForEach(group.children) { child in
                    sessionButton(child)
                        .padding(.leading, 22)
                        .id(child.id)
                }
            }
        }
    }

    private func sessionButton(_ session: AgentSession) -> some View {
        Button {
            selection = session.id
        } label: {
            ActivitySessionRow(session: session, isSelected: selection == session.id)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Origin") { runtime.open(session) }
            if !session.isActive {
                Button("Remove from History", role: .destructive) {
                    runtime.activity.removeSession(id: session.id)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.task)
        .accessibilityValue("\(session.provider.displayName), \(session.state.displayName), \(session.currentActivity)")
        .accessibilityAddTraits(selection == session.id ? .isSelected : [])
    }

    @ViewBuilder
    private var detail: some View {
        if let session = selectedSession {
            ActivitySessionDetailView(
                session: session,
                parent: projection.parent(of: session),
                children: projection.children(of: session.id),
                onOpen: { runtime.open(session) },
                onOpenFile: runtime.openFile,
                onSelectSession: { revealAndSelect($0) }
            )
        } else {
            VStack(spacing: 10) {
                NotchShape(bottomRadius: 12)
                    .fill(.white.opacity(0.09))
                    .frame(width: 66, height: 34)
                Text("Select a session")
                    .font(NotchWindowFont.title)
                    .foregroundStyle(.white.opacity(0.82))
                Text("Plans, workflows, files, and recent events appear here.")
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchWindowPalette.background)
        }
    }

    private var sessionCountSummary: String {
        let count = projection.sessionCount
        return count == 1 ? "1 session on this Mac" : "\(count) sessions on this Mac"
    }

    private var selectedSession: AgentSession? {
        guard let selection else { return nil }
        return projection.session(id: selection)
    }

    private var statusFilter: ActivityStatusFilter {
        ActivityStatusFilter(rawValue: statusFilterRaw) ?? .all
    }

    private var dateFilter: ActivityDateFilter {
        ActivityDateFilter(rawValue: dateFilterRaw) ?? .all
    }

    private var groupingMode: ActivityGroupingMode {
        ActivityGroupingMode(rawValue: groupingModeRaw) ?? .grouped
    }

    private var statusFilterBinding: Binding<ActivityStatusFilter> {
        Binding(
            get: { statusFilter },
            set: { statusFilterRaw = $0.rawValue }
        )
    }

    private var dateFilterBinding: Binding<ActivityDateFilter> {
        Binding(
            get: { dateFilter },
            set: { dateFilterRaw = $0.rawValue }
        )
    }

    private var groupingModeBinding: Binding<ActivityGroupingMode> {
        Binding(
            get: { groupingMode },
            set: { groupingModeRaw = $0.rawValue }
        )
    }

    private var visibleSessionIDs: [String] {
        guard groupingMode == .grouped else { return projection.filteredSessions.map(\.id) }
        return projection.projectGroups.flatMap { project in
            project.groups.flatMap { group in
                [group.root.id] + (expandedGroupIDs.contains(group.id) ? group.children.map(\.id) : [])
            }
        }
    }

    private func revealAndSelect(_ sessionID: String) {
        providerFilter = "all"
        statusFilterRaw = ActivityStatusFilter.all.rawValue
        projectFilter = "all"
        dateFilterRaw = ActivityDateFilter.all.rawValue
        searchText = ""
        expandGroup(containing: sessionID)
        selection = sessionID
    }

    private func synchronizeSelection() {
        if let requested = runtime.requestedSessionID,
           projection.session(id: requested) != nil {
            revealAndSelect(requested)
            runtime.consumeRequestedSession(requested)
            return
        }
        if projectFilter != "all", !projection.availableProjects.contains(where: { $0.id == projectFilter }) {
            projectFilter = "all"
            return
        }
        if providerFilter != "all", !projection.availableProviders.contains(where: { $0.rawValue == providerFilter }) {
            providerFilter = "all"
            return
        }
        if let selection, projection.filteredSessionIDs.contains(selection) {
            expandGroup(containing: selection)
            return
        }
        selection = visibleSessionIDs.first ?? projection.filteredSessions.first?.id
    }

    private func refreshProjection() {
        projection.update(
            sessions: runtime.activity.sessions,
            searchText: searchText,
            providerFilter: providerFilter,
            statusFilter: statusFilter,
            projectFilter: projectFilter,
            dateFilter: dateFilter
        )
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expandedGroupIDs.formUnion(projection.projectGroups.flatMap { $0.groups.map(\.id) })
        }
    }

    private func scheduleSearchRefresh() {
        searchTask?.cancel()
        guard !searchText.isEmpty else {
            refreshProjection()
            synchronizeSelection()
            return
        }
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            refreshProjection()
            synchronizeSelection()
        }
    }

    private func toggleGroup(_ groupID: String) {
        if expandedGroupIDs.contains(groupID) {
            expandedGroupIDs.remove(groupID)
        } else {
            expandedGroupIDs.insert(groupID)
        }
    }

    private func expandGroup(containing sessionID: String) {
        guard let groupID = projection.groupID(containing: sessionID) else { return }
        expandedGroupIDs.insert(groupID)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down else { return }
        let ids = visibleSessionIDs
        guard !ids.isEmpty else { return }
        guard let selection, let currentIndex = ids.firstIndex(of: selection) else {
            self.selection = ids.first
            return
        }
        let offset = direction == .down ? 1 : -1
        let nextIndex = min(max(currentIndex + offset, 0), ids.count - 1)
        self.selection = ids[nextIndex]
    }

    private func openSelectedSession() {
        guard let selectedSession else { return }
        runtime.open(selectedSession)
    }

    private func removeSelectedSession() {
        guard let selectedSession, !selectedSession.isActive else { return }
        runtime.activity.removeSession(id: selectedSession.id)
    }

    private func handleSearchRequest() {
        guard handledSearchRequest != runtime.activitySearchRequest else { return }
        handledSearchRequest = runtime.activitySearchRequest
        isSearchFocused = true
    }
}

struct ActivityProjectOption: Identifiable, Equatable {
    let id: String
    let title: String
}

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

    var sessionCount: Int {
        groups.reduce(0) { $0 + 1 + $1.children.count }
    }
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

        static let empty = State(
            filteredSessions: [],
            filteredSessionIDs: [],
            availableProviders: [],
            availableProjects: [],
            projectGroups: [],
            sessionCount: 0,
            hasRecentSessions: false
        )
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

    func session(id: String) -> AgentSession? {
        sessionsByID[id]
    }

    func parent(of session: AgentSession) -> AgentSession? {
        session.parentSessionId.flatMap { sessionsByID[$0] }
    }

    func children(of sessionID: String) -> [AgentSession] {
        childrenByParentID[sessionID] ?? []
    }

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
        var sessionsByID: [String: AgentSession] = [:]
        var childrenByParentID: [String: [AgentSession]] = [:]
        var providers = Set<AgentProvider>()
        sessionsByID.reserveCapacity(sessions.count)
        for session in sessions {
            sessionsByID[session.id] = session
            providers.insert(session.provider)
            if let parentID = session.parentSessionId {
                childrenByParentID[parentID, default: []].append(session)
            }
        }
        for parentID in childrenByParentID.keys {
            childrenByParentID[parentID]?.sort(by: Self.orderSessions)
        }
        self.sessionsByID = sessionsByID
        self.childrenByParentID = childrenByParentID

        let projectKeyBySessionID = Dictionary(uniqueKeysWithValues: sessions.map { session in
            let rootID = Self.rootID(for: session.id, sessionsByID: sessionsByID)
            let root = sessionsByID[rootID] ?? session
            return (session.id, root.workingDirectory ?? session.workingDirectory ?? "provider:\(root.provider.rawValue)")
        })
        let projectTitles = Dictionary(grouping: sessions, by: { projectKeyBySessionID[$0.id] ?? "provider:\($0.provider.rawValue)" })
            .mapValues { candidates in
                let directory = candidates.compactMap(\.workingDirectory).first
                return directory.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? candidates.first?.provider.displayName
                    ?? "Unknown project"
            }
        let availableProjects = projectTitles
            .map { ActivityProjectOption(id: $0.key, title: $0.value) }
            .sorted {
                if $0.title != $1.title { return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return $0.id < $1.id
            }

        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = sessions.filter { session in
            guard providerFilter == "all" || session.provider.rawValue == providerFilter else {
                return false
            }
            guard projectFilter == "all" || projectKeyBySessionID[session.id] == projectFilter else {
                return false
            }
            guard dateFilter.includes(session.updatedAt, now: now) else { return false }
            let statusMatches = switch statusFilter {
            case .all: true
            case .active: session.isActive
            case .attention: session.state == .waitingForUser
            case .completed: !session.isActive
            }
            guard statusMatches, !normalizedSearch.isEmpty else { return statusMatches }
            let haystack = Self.searchText(for: session)
            return haystack.localizedCaseInsensitiveContains(normalizedSearch)
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id < rhs.id
        }

        let projectGroups = Self.makeProjectGroups(
            matchingSessions: filtered,
            sessionsByID: sessionsByID,
            projectKeyBySessionID: projectKeyBySessionID,
            projectTitles: projectTitles
        )
        let contextualRootIDs = Set(projectGroups.flatMap { $0.groups.map(\.root.id) })

        let nextState = State(
            filteredSessions: filtered,
            filteredSessionIDs: Set(filtered.map(\.id)).union(contextualRootIDs),
            availableProviders: providers.sorted { $0.displayName < $1.displayName },
            availableProjects: availableProjects,
            projectGroups: projectGroups,
            sessionCount: sessions.count,
            hasRecentSessions: sessions.contains { !$0.isActive }
        )
        if nextState != state {
            state = nextState
        }
    }

    private static func orderSessions(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id < rhs.id
    }

    private static func rootID(
        for sessionID: String,
        sessionsByID: [String: AgentSession]
    ) -> String {
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
        let matchesByRoot = Dictionary(grouping: matchingSessions) {
            rootID(for: $0.id, sessionsByID: sessionsByID)
        }
        var groupsByProject: [String: [ActivitySessionGroup]] = [:]

        for (rootID, matches) in matchesByRoot {
            guard let fallback = matches.first else { continue }
            let root = sessionsByID[rootID] ?? fallback
            let children = matches
                .filter { $0.id != root.id }
                .sorted(by: orderSessions)
            let latest = ([root] + children).map(\.updatedAt).max() ?? root.updatedAt
            let group = ActivitySessionGroup(root: root, children: children, latestUpdatedAt: latest)
            let projectID = projectKeyBySessionID[root.id]
                ?? projectKeyBySessionID[fallback.id]
                ?? "provider:\(root.provider.rawValue)"
            groupsByProject[projectID, default: []].append(group)
        }

        return groupsByProject.map { projectID, groups in
            let sortedGroups = groups.sorted {
                if $0.latestUpdatedAt != $1.latestUpdatedAt { return $0.latestUpdatedAt > $1.latestUpdatedAt }
                return $0.id < $1.id
            }
            return ActivityProjectSection(
                id: projectID,
                title: projectTitles[projectID] ?? "Unknown project",
                groups: sortedGroups,
                latestUpdatedAt: sortedGroups.map(\.latestUpdatedAt).max() ?? .distantPast
            )
        }
        .sorted {
            if $0.latestUpdatedAt != $1.latestUpdatedAt { return $0.latestUpdatedAt > $1.latestUpdatedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func searchText(for session: AgentSession) -> String {
        var values = [
            session.task,
            session.currentActivity,
            session.workingDirectory ?? "",
            session.provider.displayName,
            session.agentRole ?? "",
        ]
        values.append(contentsOf: session.recentFiles)
        values.append(contentsOf: session.recentEvents.map {
            [$0.activity, $0.file, $0.resolvedState.displayName]
                .compactMap { $0 }
                .joined(separator: " ")
        })
        if let plan = session.plan {
            values.append(plan.title ?? "")
            values.append(plan.explanation ?? "")
            values.append(contentsOf: plan.steps.flatMap { [$0.title, $0.status.displayName] })
        }
        for workflow in session.workflows {
            values.append(workflow.title)
            values.append(workflow.status.displayName)
            values.append(contentsOf: workflow.steps.flatMap { [$0.title, $0.status.displayName] })
        }
        return values.joined(separator: " ")
    }
}
