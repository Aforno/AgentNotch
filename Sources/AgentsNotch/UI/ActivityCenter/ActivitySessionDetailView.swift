import AgentsNotchCore
import SwiftUI

struct ActivitySessionDetailView: View {
    let session: AgentSession
    let parent: AgentSession?
    let children: [AgentSession]
    let onOpen: () -> Void
    let onOpenFile: (String) -> Void
    let onSelectSession: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotchWindowMetrics.sectionSpacing) {
                header

                if let plan = session.plan {
                    detailSection("Plan", count: "\(plan.completedStepCount)/\(plan.steps.count)") {
                        ForEach(plan.steps) { step in stepRow(step) }
                    }
                }

                ForEach(session.workflows) { workflow in
                    detailSection(workflow.title, count: workflow.status.displayName) {
                        if workflow.steps.isEmpty {
                            Text(workflow.status.displayName)
                                .font(NotchWindowFont.caption)
                                .foregroundStyle(NotchWindowPalette.secondaryText)
                        } else {
                            ForEach(workflow.steps) { step in stepRow(step) }
                        }
                    }
                }

                if parent != nil || !children.isEmpty {
                    detailSection("Agent Group", count: "\((parent == nil ? 0 : 1) + children.count)") {
                        if let parent { relationshipRow(parent, label: "Parent") }
                        ForEach(children) { child in
                            relationshipRow(child, label: child.agentRole ?? "Subagent")
                        }
                    }
                }

                if !session.recentFiles.isEmpty {
                    detailSection("Recent Files", count: "\(session.recentFiles.count)") {
                        ForEach(session.recentFiles, id: \.self) { path in
                            Button { onOpenFile(path) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(NotchWindowFont.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(path)
                        }
                    }
                }

                detailSection("Recent Events", count: "\(session.recentEvents.count)") {
                    ActivityEventTimeline(events: session.recentEvents)
                }
            }
            .padding(NotchWindowMetrics.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NotchWindowPalette.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ProviderIconView(provider: session.provider, size: 20)

                Text(session.provider.displayName)
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(.white.opacity(0.82))

                HStack(spacing: 5) {
                    StateIndicator(state: session.state, size: 8)
                    Text(session.state.displayName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(agentStateColor(for: session.state))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: Capsule())

                Spacer()

                Text(session.updatedAt, style: .relative)
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)

                Button(action: onOpen) {
                    Label("Open Origin", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(NotchPillButtonStyle())
            }

            Text(session.task)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)

            Text(session.currentActivity)
                .font(.system(size: 12))
                .foregroundStyle(NotchWindowPalette.secondaryText)

            if let directory = session.workingDirectory {
                Label(directory, systemImage: "folder")
                    .font(NotchWindowFont.mono)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                    .textSelection(.enabled)
            }
        }
        .padding(.bottom, 2)
    }

    private func detailSection<Content: View>(
        _ title: String,
        count: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            NotchSectionLabel(title: title, trailing: count)

            VStack(alignment: .leading, spacing: 9) {
                content()
            }
            .padding(NotchWindowMetrics.rowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)
        }
    }

    private func stepRow(_ step: AgentStep) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol(for: step.status))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color(for: step.status))
                .frame(width: 14)
            Text(step.title)
                .font(NotchWindowFont.caption)
                .foregroundStyle(step.status == .completed ? .white.opacity(0.42) : .white.opacity(0.8))
                .strikethrough(step.status == .completed, color: .white.opacity(0.24))
            Spacer()
            Text(step.status.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color(for: step.status).opacity(0.8))
        }
    }

    private func relationshipRow(_ related: AgentSession, label: String) -> some View {
        Button {
            onSelectSession(related.id)
        } label: {
            HStack(spacing: 9) {
                ProviderIconView(provider: related.provider, size: 15)
                Text(label.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule())
                Text(related.task)
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .lineLimit(1)
                Spacer()
                StateIndicator(state: related.state, size: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func symbol(for status: AgentStepStatus) -> String {
        switch status {
        case .pending: "circle"
        case .inProgress: "circle.fill"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .blocked: "exclamationmark"
        }
    }

    private func color(for status: AgentStepStatus) -> Color {
        switch status {
        case .pending: NotchWindowPalette.tertiaryText
        case .inProgress: .blue
        case .completed: .green
        case .failed: .red
        case .blocked: .orange
        }
    }
}
