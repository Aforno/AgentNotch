import AgentsNotchCore
import SwiftUI

struct ActivitySessionDetailView: View {
    let session: AgentSession
    let parent: AgentSession?
    let children: [AgentSession]
    let onOpen: (OriginOpenAction) -> Void
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
                                        .font(NotchWindowFont.footnote)
                                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(NotchWindowFont.caption)
                                        .foregroundStyle(NotchWindowPalette.primaryText)
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                        .font(NotchWindowFont.glyph)
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

    /// Title and actions share the top line; everything else is one quiet
    /// metadata line so the header stays two rows at any window width.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                Text(session.task)
                    .font(NotchWindowFont.display)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(OriginActivationService.destinations(for: session), id: \.action) { destination in
                        Button {
                            onOpen(destination.action)
                        } label: {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                        .buttonStyle(NotchPillButtonStyle())
                    }
                }
                .fixedSize()
            }

            HStack(spacing: 6) {
                ProviderIconView(provider: session.provider, size: 13)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                Text(session.provider.displayName)
                separatorDot
                StateIndicator(state: session.state, size: 8)
                Text(session.state.displayName)
                    .foregroundStyle(agentStateColor(for: session.state))
                separatorDot
                ElapsedLabel(since: session.updatedAt, phrased: true)
            }
            .font(NotchWindowFont.caption)
            .foregroundStyle(NotchWindowPalette.secondaryText)

            Text(session.currentActivity)
                .font(NotchWindowFont.body)
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

    private var separatorDot: some View {
        Text("·").foregroundStyle(NotchWindowPalette.quaternaryText)
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
            Image(systemName: StepStatusStyle.systemImage(for: step.status))
                .font(NotchWindowFont.footnoteEmphasis)
                .foregroundStyle(StepStatusStyle.color(for: step.status))
                .frame(width: 14)
            Text(step.title)
                .font(NotchWindowFont.caption)
                .foregroundStyle(
                    step.status == .completed
                        ? NotchWindowPalette.tertiaryText
                        : NotchWindowPalette.primaryText
                )
                .strikethrough(step.status == .completed, color: NotchWindowPalette.quaternaryText)
            Spacer()
            Text(step.status.displayName)
                .font(NotchWindowFont.footnote)
                .foregroundStyle(StepStatusStyle.color(for: step.status))
        }
    }

    private func relationshipRow(_ related: AgentSession, label: String) -> some View {
        Button {
            onSelectSession(related.id)
        } label: {
            HStack(spacing: 9) {
                ProviderIconView(provider: related.provider, size: 15)
                Text(AgentRowPresentation.formattedRole(label))
                    .font(NotchWindowFont.footnoteEmphasis)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(NotchWindowPalette.raisedStrong, in: Capsule())
                Text(related.task)
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .lineLimit(1)
                Spacer()
                StateIndicator(state: related.state, size: 8)
                Image(systemName: "chevron.right")
                    .font(NotchWindowFont.glyph)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
