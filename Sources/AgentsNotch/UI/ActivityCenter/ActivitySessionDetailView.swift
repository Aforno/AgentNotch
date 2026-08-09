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
            VStack(alignment: .leading, spacing: 14) {
                header

                if let plan = session.plan {
                    detailSection("Plan", count: "\(plan.completedStepCount)/\(plan.steps.count)") {
                        ForEach(plan.steps) { step in stepRow(step) }
                    }
                }

                ForEach(session.workflows) { workflow in
                    detailSection(workflow.title, count: workflow.status.displayName.uppercased()) {
                        if workflow.steps.isEmpty {
                            Text(workflow.status.displayName)
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
                                        .foregroundStyle(NotchWindowPalette.secondaryText)
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption2.weight(.bold))
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
                    ForEach(session.recentEvents) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(event.timestamp, style: .time)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(NotchWindowPalette.tertiaryText)
                                .frame(width: 64, alignment: .leading)
                            Text(event.activity ?? event.resolvedState.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.72))
                            Spacer()
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NotchWindowPalette.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProviderIconView(provider: session.provider, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.provider.displayName.uppercased())
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                    HStack(spacing: 5) {
                        StateIndicator(state: session.state, size: 8)
                        Text(session.state.displayName.uppercased())
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(activityColor(for: session.state))
                }

                Spacer()

                Text(session.updatedAt, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NotchWindowPalette.secondaryText)

                Button(action: onOpen) {
                    Label("OPEN ORIGIN", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(ActivityActionButtonStyle())
            }

            Rectangle()
                .fill(NotchWindowPalette.border)
                .frame(height: 1)

            Text(session.task)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .tracking(-0.6)

            Text(session.currentActivity)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchWindowPalette.secondaryText)

            if let directory = session.workingDirectory {
                Label(directory, systemImage: "folder")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .notchPanel(cornerRadius: 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(activityColor(for: session.state))
                .frame(height: 3)
                .padding(.horizontal, 13)
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        count: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                Spacer()
                Text(count)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Rectangle()
                .fill(NotchWindowPalette.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .notchPanel()
    }

    private func stepRow(_ step: AgentStep) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: step.status))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color(for: step.status))
                .frame(width: 15)
            Text(step.title)
                .font(.system(size: 11))
                .foregroundStyle(step.status == .completed ? .white.opacity(0.42) : .white.opacity(0.8))
                .strikethrough(step.status == .completed, color: .white.opacity(0.24))
            Spacer()
            Text(step.status.displayName.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(color(for: step.status).opacity(0.8))
        }
    }

    private func relationshipRow(_ related: AgentSession, label: String) -> some View {
        Button {
            onSelectSession(related.id)
        } label: {
            HStack(spacing: 9) {
                ProviderIconView(provider: related.provider, size: 15)
                Text(label.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                Text(related.task)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .lineLimit(1)
                Spacer()
                StateIndicator(state: related.state, size: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
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

