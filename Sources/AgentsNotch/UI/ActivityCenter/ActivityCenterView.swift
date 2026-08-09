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
        var title: String { rawValue.uppercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(NotchWindowPalette.border)
                .frame(height: 1)

            HStack(spacing: 0) {
                sidebar
                    .frame(minWidth: 270, idealWidth: 300, maxWidth: 340)

                Rectangle()
                    .fill(NotchWindowPalette.border)
                    .frame(width: 1)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTIVITY CENTER")
                    .font(.system(size: 23, weight: .black, design: .monospaced))
                    .tracking(-1)
                Text("LOCAL AGENT HISTORY / \(runtime.activity.sessions.count) SESSIONS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }

            Spacer()

            ActivityMetric(
                title: "ACTIVE",
                value: runtime.activity.activeSessions.count,
                color: .blue
            )
            ActivityMetric(
                title: "ATTENTION",
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
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .overlay {
                Rectangle().stroke(NotchWindowPalette.border, lineWidth: 1)
            }
            .help("Activity options")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(NotchWindowPalette.background)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            filterControls

            Rectangle()
                .fill(NotchWindowPalette.border)
                .frame(height: 1)

            if filteredSessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                    Text("NO MATCHING SESSIONS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredSessions) { session in
                            sessionButton(session)
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.visible)
            }
        }
        .background(NotchWindowPalette.background)
    }

    private var filterControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NotchWindowPalette.secondaryText)

                TextField("SEARCH SESSIONS", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(NotchWindowPalette.raised)
            .overlay {
                Rectangle().stroke(NotchWindowPalette.border, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Picker("Provider", selection: $providerFilter) {
                    Text("ALL PROVIDERS").tag("all")
                    ForEach(availableProviders) { provider in
                        Text(provider.displayName.uppercased()).tag(provider.rawValue)
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
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .controlSize(.small)
        }
        .padding(12)
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
            VStack(spacing: 14) {
                NotchShape(bottomRadius: 13)
                    .fill(.white.opacity(0.12))
                    .frame(width: 70, height: 38)
                Text("SELECT A SESSION")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                Text("Plans, workflows, files, and recent events appear here.")
                    .font(.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchWindowPalette.background)
        }
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

