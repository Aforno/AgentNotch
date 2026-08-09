import AgentsNotchCore
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let children: [AgentSession]

    static let executionRowHeight: CGFloat = 62

    static func preferredHeight(for session: AgentSession, children: [AgentSession]) -> CGFloat {
        hasSecondarySummary(for: session, children: children)
            ? executionRowHeight
            : DynamicIslandSpacing.rowHeight
    }

    private static func hasSecondarySummary(for session: AgentSession, children: [AgentSession]) -> Bool {
        // Workflow progress is presented inline with its current stage. Keeping
        // those rows at the standard height avoids repeating workflow context
        // across two lines.
        guard session.workflows.isEmpty else { return false }
        return session.plan?.steps.isEmpty == false || !children.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: DynamicIslandSpacing.standard) {
                if session.isSubagent {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 10)
                }

                ProviderIconView(provider: session.provider, size: 14)
                    .foregroundStyle(.white.opacity(0.9))

                Text(session.isSubagent ? subagentLabel : session.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: session.isSubagent ? 78 : 62, alignment: .leading)

                if let workflow = session.workflows.first {
                    WorkflowInlineSummary(workflow: workflow, children: children)
                } else {
                    Text(session.currentActivity)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }

                Spacer(minLength: DynamicIslandSpacing.related)

                StateIndicator(state: session.state, size: 12)
            }

            if hasSecondarySummary {
                AgentRowExecutionSummary(session: session, children: children)
                    .padding(.leading, session.isSubagent ? 34 : 24)
            }
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .frame(
            height: Self.preferredHeight(for: session, children: children),
            alignment: .center
        )
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var subagentLabel: String {
        session.agentRole?
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .capitalized ?? "Subagent"
    }

    private var hasSecondarySummary: Bool {
        Self.hasSecondarySummary(for: session, children: children)
    }

    private var accessibilityLabel: String {
        let identity = session.isSubagent
            ? "\(subagentLabel) subagent"
            : session.provider.displayName
        if let workflow = session.workflows.first {
            let active = children.filter(\.isActive).count
            let agents = active == 1 ? "1 active agent" : "\(active) active agents"
            return "\(identity), \(workflow.rowProgress), \(workflow.rowStage), \(agents), \(session.state.displayName)"
        }
        return "\(identity), \(session.currentActivity), \(session.state.displayName)"
    }
}

private struct WorkflowInlineSummary: View {
    let workflow: AgentWorkflow
    let children: [AgentSession]

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Text(workflow.rowProgress)
            Text(workflow.rowStage)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text("\(activeAgentCount) active")
            }
            .foregroundStyle(.white.opacity(0.46))
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }

    private var activeAgentCount: Int {
        children.filter(\.isActive).count
    }
}

private extension AgentWorkflow {
    var rowProgress: String {
        guard !steps.isEmpty else { return status.displayName }
        let completed = steps.filter { $0.status == .completed }.count
        return "\(completed)/\(steps.count)"
    }

    var rowStage: String {
        let current = steps.first {
            $0.status == .inProgress || $0.status == .failed || $0.status == .blocked
        }
        if let current { return current.title }
        if status == .completed, let final = steps.last { return final.title }
        if let pending = steps.first(where: { $0.status == .pending }) { return pending.title }
        return status.displayName
    }
}

private struct AgentRowExecutionSummary: View {
    let session: AgentSession
    let children: [AgentSession]

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.standard) {
            if let plan = session.plan, !plan.steps.isEmpty {
                HStack(spacing: 5) {
                    StepStatusStrip(steps: plan.steps)
                    Text("\(plan.completedStepCount)/\(plan.steps.count) steps")
                }
            }

            if !children.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(childSummary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.42))
    }

    private var childSummary: String {
        let active = children.filter(\.isActive).count
        let waiting = children.filter(\.needsAttention).count
        if waiting > 0 { return "\(children.count) agents · \(waiting) waiting" }
        return "\(children.count) agents · \(active) active"
    }
}

private struct StepStatusStrip: View {
    let steps: [AgentStep]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(steps.prefix(6)) { step in
                Capsule()
                    .fill(color(for: step.status))
                    .frame(width: 8, height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for status: AgentStepStatus) -> Color {
        switch status {
        case .pending: .white.opacity(0.18)
        case .inProgress: .blue
        case .completed: .green
        case .failed: .red
        case .blocked: .orange
        }
    }
}
