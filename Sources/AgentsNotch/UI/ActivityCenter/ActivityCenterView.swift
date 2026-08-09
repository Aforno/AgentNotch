import AgentsNotchCore
import SwiftUI

struct ActivityCenterView: View {
    let runtime: AppRuntime

    @State private var selection: String?
    @State private var searchText = ""
    @State private var providerFilter = "all"
    @State private var statusFilter = StatusFilter.all
    @State private var confirmsClearHistory = false

    private enum StatusFilter: String, CaseIterable, Identifiable {
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
        .onAppear { synchronizeSelection() }
        .onChange(of: filteredSessions.map(\.id)) { _, _ in synchronizeSelection() }
        .onChange(of: runtime.requestedSessionID) { _, requested in
            guard let requested else { return }
            revealAndSelect(requested)
            runtime.consumeRequestedSession(requested)
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
                value: runtime.activity.activeSessions.count,
                color: .blue
            )
            ActivityMetric(
                title: "Attention",
                value: runtime.activity.attentionCount,
                color: .orange
            )

            Menu {
                Button("Clear Completed History", role: .destructive) {
                    confirmsClearHistory = true
                }
                .disabled(runtime.activity.recentSessions.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .frame(width: 28, height: 28)
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

            if filteredSessions.isEmpty {
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
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredSessions) { session in
                            sessionButton(session)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.visible)
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
                Picker("Provider", selection: $providerFilter) {
                    Text("All providers").tag("all")
                    ForEach(availableProviders) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }
            .font(NotchWindowFont.control)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
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
        .accessibilityAddTraits(selection == session.id ? .isSelected : [])
    }

    @ViewBuilder
    private var detail: some View {
        if let session = selectedSession {
            ActivitySessionDetailView(
                session: session,
                parent: runtime.activity.parent(of: session),
                children: runtime.activity.children(of: session.id),
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
        let count = runtime.activity.sessions.count
        return count == 1 ? "1 session on this Mac" : "\(count) sessions on this Mac"
    }

    private var filteredSessions: [AgentSession] {
        runtime.activity.sessions
            .filter { providerFilter == "all" || $0.provider.rawValue == providerFilter }
            .filter { session in
                switch statusFilter {
                case .all: true
                case .active: session.isActive
                case .attention: session.state == .waitingForUser
                case .completed: !session.isActive
                }
            }
            .filter { session in
                guard !searchText.isEmpty else { return true }
                let haystack = [
                    session.task,
                    session.currentActivity,
                    session.workingDirectory ?? "",
                    session.provider.displayName,
                    session.agentRole ?? "",
                ].joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var availableProviders: [AgentProvider] {
        Array(Set(runtime.activity.sessions.map(\.provider)))
            .sorted { $0.displayName < $1.displayName }
    }

    private var selectedSession: AgentSession? {
        guard let selection else { return nil }
        return runtime.activity.sessions.first { $0.id == selection }
    }

    private func revealAndSelect(_ sessionID: String) {
        providerFilter = "all"
        statusFilter = .all
        searchText = ""
        selection = sessionID
    }

    private func synchronizeSelection() {
        if let requested = runtime.requestedSessionID,
           runtime.activity.sessions.contains(where: { $0.id == requested }) {
            revealAndSelect(requested)
            runtime.consumeRequestedSession(requested)
            return
        }
        if let selection, filteredSessions.contains(where: { $0.id == selection }) { return }
        selection = filteredSessions.first?.id
    }
}

