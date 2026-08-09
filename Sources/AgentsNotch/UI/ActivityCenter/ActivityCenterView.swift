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
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredSessions, selection: $selection) { session in
                ActivitySessionRow(session: session)
                    .tag(session.id)
                    .contextMenu {
                        Button("Open Origin") { runtime.open(session) }
                        if !session.isActive {
                            Button("Remove from History", role: .destructive) {
                                runtime.activity.removeSession(id: session.id)
                            }
                        }
                    }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 250)
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
            .searchable(text: $searchText, prompt: "Search sessions")
            .toolbar {
                ToolbarItemGroup {
                    Picker("Provider", selection: $providerFilter) {
                        Text("All Providers").tag("all")
                        ForEach(availableProviders) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 135)

                    Picker("Status", selection: $statusFilter) {
                        ForEach(StatusFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 105)
                }
            }
        } detail: {
            if let session = selectedSession {
                ActivitySessionDetailView(
                    session: session,
                    parent: runtime.activity.parent(of: session),
                    children: runtime.activity.children(of: session.id),
                    onOpen: { runtime.open(session) },
                    onOpenFile: runtime.openFile,
                    onSelectSession: { selection = $0 }
                )
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "waveform.path.ecg",
                    description: Text("Plans, workflows, files, and recent events appear here.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Clear Completed History", role: .destructive) {
                        confirmsClearHistory = true
                    }
                    .disabled(runtime.activity.recentSessions.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Activity options")
            }
        }
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
            selection = requested
            runtime.consumeRequestedSession(requested)
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

    private func synchronizeSelection() {
        if let requested = runtime.requestedSessionID,
           runtime.activity.sessions.contains(where: { $0.id == requested }) {
            selection = requested
            runtime.consumeRequestedSession(requested)
            return
        }
        if let selection, filteredSessions.contains(where: { $0.id == selection }) { return }
        selection = filteredSessions.first?.id
    }
}

private struct ActivitySessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(provider: session.provider, size: 17)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.task)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            StateIndicator(state: session.state, size: 10)
        }
        .padding(.vertical, 2)
    }

    private var rowDetail: String {
        let project = session.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
        return [project, session.currentActivity].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ActivitySessionDetailView: View {
    let session: AgentSession
    let parent: AgentSession?
    let children: [AgentSession]
    let onOpen: () -> Void
    let onOpenFile: (String) -> Void
    let onSelectSession: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let plan = session.plan {
                    detailSection("Plan") {
                        ForEach(plan.steps) { step in stepRow(step) }
                    }
                }

                ForEach(session.workflows) { workflow in
                    detailSection(workflow.title) {
                        if workflow.steps.isEmpty {
                            Text(workflow.status.displayName).foregroundStyle(.secondary)
                        } else {
                            ForEach(workflow.steps) { step in stepRow(step) }
                        }
                    }
                }

                if parent != nil || !children.isEmpty {
                    detailSection("Agent Group") {
                        if let parent { relationshipRow(parent, label: "Parent") }
                        ForEach(children) { child in relationshipRow(child, label: child.agentRole ?? "Subagent") }
                    }
                }

                if !session.recentFiles.isEmpty {
                    detailSection("Recent Files") {
                        ForEach(session.recentFiles, id: \.self) { path in
                            Button { onOpenFile(path) } label: {
                                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .help(path)
                        }
                    }
                }

                detailSection("Recent Events") {
                    ForEach(session.recentEvents) { event in
                        HStack(alignment: .firstTextBaseline) {
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 70, alignment: .leading)
                            Text(event.activity ?? event.resolvedState.displayName)
                            Spacer()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            Button(action: onOpen) {
                Label("Open Origin", systemImage: "arrow.up.forward.app")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StateIndicator(state: session.state, size: 12)
                Text(session.state.displayName)
                    .foregroundStyle(session.needsAttention ? .orange : .secondary)
                Spacer()
                Text(session.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Text(session.task)
                .font(.title2.weight(.semibold))
            Text(session.currentActivity)
                .foregroundStyle(.secondary)
            if let directory = session.workingDirectory {
                Label(directory, systemImage: "folder")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 9) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private func stepRow(_ step: AgentStep) -> some View {
        HStack {
            Image(systemName: symbol(for: step.status))
                .foregroundStyle(color(for: step.status))
                .frame(width: 16)
            Text(step.title)
            Spacer()
        }
    }

    private func relationshipRow(_ related: AgentSession, label: String) -> some View {
        Button {
            onSelectSession(related.id)
        } label: {
            HStack {
                ProviderIconView(provider: related.provider, size: 14)
                Text(label.replacingOccurrences(of: "_", with: " ").capitalized)
                    .fontWeight(.medium)
                Text(related.task)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                StateIndicator(state: related.state, size: 9)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func symbol(for status: AgentStepStatus) -> String {
        switch status {
        case .pending: "circle"
        case .inProgress: "circle.dotted"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .blocked: "exclamationmark.circle.fill"
        }
    }

    private func color(for status: AgentStepStatus) -> Color {
        switch status {
        case .pending: .secondary
        case .inProgress: .blue
        case .completed: .green
        case .failed: .red
        case .blocked: .orange
        }
    }
}
