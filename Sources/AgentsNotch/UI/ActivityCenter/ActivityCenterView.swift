import AgentsNotchCore
import SwiftUI

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
    @FocusState private var isSessionListFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ActivityCenterHeader(
                sessionCount: projection.sessionCount,
                activeCount: runtime.activity.notchSnapshot.activeSessions.count,
                attentionCount: runtime.activity.notchSnapshot.attentionCount,
                groupingMode: groupingModeBinding,
                canClearHistory: projection.hasRecentSessions,
                requestClearHistory: { confirmsClearHistory = true }
            )

            NotchHairline()

            HStack(spacing: 0) {
                sidebar
                    .frame(minWidth: 270, idealWidth: 300, maxWidth: 340)
                    // Arrow / return / delete need the column to take focus.
                    // The default ring is a blue rectangle around the sidebar.
                    .focusable()
                    .focused($isSessionListFocused)
                    .focusEffectDisabled()

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

    private var sidebar: some View {
        ActivityCenterSidebar(
            projection: projection,
            searchText: $searchText,
            providerFilter: $providerFilter,
            statusFilter: statusFilterBinding,
            projectFilter: $projectFilter,
            dateFilter: dateFilterBinding,
            groupingMode: groupingMode,
            selection: selection,
            expandedGroupIDs: expandedGroupIDs,
            isSearchFocused: $isSearchFocused,
            onSelect: { sessionID in
                selection = sessionID
                isSearchFocused = false
                isSessionListFocused = true
            },
            onToggleGroup: toggleGroup,
            onOpen: runtime.open,
            onRemove: { runtime.activity.removeSession(id: $0) }
        )
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
            ActivityCenterEmptyDetail()
        }
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
        isSessionListFocused = false
        isSearchFocused = true
    }
}
