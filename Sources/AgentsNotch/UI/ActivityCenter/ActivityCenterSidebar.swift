import AgentsNotchCore
import SwiftUI

struct ActivityCenterSidebar: View {
    let projection: ActivityCenterProjection
    @Binding var searchText: String
    @Binding var providerFilter: String
    @Binding var statusFilter: ActivityStatusFilter
    @Binding var projectFilter: String
    @Binding var dateFilter: ActivityDateFilter
    let groupingMode: ActivityGroupingMode
    let selection: String?
    let expandedGroupIDs: Set<String>
    @FocusState.Binding var isSearchFocused: Bool
    let onSelect: (String) -> Void
    let onToggleGroup: (String) -> Void
    let onOpen: (AgentSession) -> Void
    let onRemove: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ActivityFilterBar(
                projection: projection,
                searchText: $searchText,
                providerFilter: $providerFilter,
                statusFilter: $statusFilter,
                projectFilter: $projectFilter,
                dateFilter: $dateFilter,
                isSearchFocused: $isSearchFocused
            )
            NotchHairline()
            sessionList
        }
        .background(NotchWindowPalette.background)
    }

    @ViewBuilder
    private var sessionList: some View {
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
                            ForEach(projection.projectGroups, content: projectSection)
                        } else {
                            ForEach(projection.filteredSessions) { sessionButton($0).id($0.id) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.visible)
                .onChange(of: selection) { _, selectedID in
                    guard let selectedID else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(selectedID, anchor: .center) }
                }
            }
        }
    }

    private func projectSection(_ project: ActivityProjectSection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 9, weight: .medium))
                Text(project.title).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(project.sessionCount)").monospacedDigit()
            }
            .font(NotchWindowFont.footnote)
            .foregroundStyle(NotchWindowPalette.tertiaryText)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
            ForEach(project.groups, content: sessionGroup)
        }
    }

    private func sessionGroup(_ group: ActivitySessionGroup) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if group.children.isEmpty {
                    Color.clear.frame(width: 20, height: 28)
                } else {
                    Button { onToggleGroup(group.id) } label: {
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
                sessionButton(group.root).id(group.root.id)
            }
            if expandedGroupIDs.contains(group.id) {
                ForEach(group.children) { child in
                    sessionButton(child).padding(.leading, 22).id(child.id)
                }
            }
        }
    }

    private func sessionButton(_ session: AgentSession) -> some View {
        Button { onSelect(session.id) } label: {
            ActivitySessionRow(session: session, isSelected: selection == session.id)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Origin") { onOpen(session) }
            if !session.isActive {
                Button("Remove from History", role: .destructive) { onRemove(session.id) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.task)
        .accessibilityValue("\(session.provider.displayName), \(session.state.displayName), \(session.currentActivity)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selection == session.id ? .isSelected : [])
    }
}

private struct ActivityFilterBar: View {
    let projection: ActivityCenterProjection
    @Binding var searchText: String
    @Binding var providerFilter: String
    @Binding var statusFilter: ActivityStatusFilter
    @Binding var projectFilter: String
    @Binding var dateFilter: ActivityDateFilter
    @FocusState.Binding var isSearchFocused: Bool

    private var activeFilterCount: Int {
        [providerFilter != "all", statusFilter != .all, projectFilter != "all", dateFilter != .all]
            .filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                TextField("Search sessions", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(NotchWindowFont.bodyEmphasis)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                        .accessibilityLabel("Clear search")
                }
                filterMenu
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(NotchWindowPalette.raised, in: RoundedRectangle(cornerRadius: NotchWindowMetrics.controlRadius, style: .continuous))

            if activeFilterCount > 0 {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        if providerFilter != "all" { filterChip(providerTitle) { providerFilter = "all" } }
                        if statusFilter != .all { filterChip(statusFilter.title) { statusFilter = .all } }
                        if projectFilter != "all" { filterChip(projectTitle) { projectFilter = "all" } }
                        if dateFilter != .all { filterChip(dateFilter.title) { dateFilter = .all } }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var filterMenu: some View {
        Menu {
            Menu("Provider") {
                Button("All providers") { providerFilter = "all" }
                ForEach(projection.availableProviders) { provider in
                    Button(provider.displayName) { providerFilter = provider.rawValue }
                }
            }
            Menu("Status") {
                ForEach(ActivityStatusFilter.allCases) { value in Button(value.title) { statusFilter = value } }
            }
            Menu("Project") {
                Button("All projects") { projectFilter = "all" }
                ForEach(projection.availableProjects) { project in Button(project.title) { projectFilter = project.id } }
            }
            Menu("Date") {
                ForEach(ActivityDateFilter.allCases) { value in Button(value.title) { dateFilter = value } }
            }
            if activeFilterCount > 0 {
                Divider()
                Button("Clear Filters") { clearFilters() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                if activeFilterCount > 0 { Text("\(activeFilterCount)").monospacedDigit() }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(activeFilterCount > 0 ? 0.9 : 0.55))
            .frame(minWidth: 24, minHeight: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter sessions")
        .accessibilityLabel(activeFilterCount == 0 ? "Filter sessions" : "Filter sessions, \(activeFilterCount) active")
    }

    private func filterChip(_ title: String, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Text(title).lineLimit(1)
            Button(action: clear) { Image(systemName: "xmark").font(.system(size: 7, weight: .bold)) }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title) filter")
        }
        .font(NotchWindowFont.footnote)
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(NotchWindowPalette.raised, in: Capsule())
    }

    private var providerTitle: String {
        projection.availableProviders.first { $0.rawValue == providerFilter }?.displayName ?? "Provider"
    }
    private var projectTitle: String {
        projection.availableProjects.first { $0.id == projectFilter }?.title ?? "Project"
    }
    private func clearFilters() {
        providerFilter = "all"; statusFilter = .all; projectFilter = "all"; dateFilter = .all
    }
}
