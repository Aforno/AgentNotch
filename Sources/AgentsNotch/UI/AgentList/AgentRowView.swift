import AgentsNotchCore
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let children: [AgentSession]

    static func preferredHeight(for _: AgentSession, children _: [AgentSession]) -> CGFloat {
        DynamicIslandSpacing.rowHeight
    }

    var body: some View {
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
                ExecutionInlineSummary(
                    progress: workflow.rowProgress,
                    stage: workflow.rowStage,
                    activeAgentCount: children.filter(\.isActive).count
                )
            } else if let plan = session.plan, !plan.steps.isEmpty {
                PlanInlineSummary(plan: plan)
            } else if !children.isEmpty {
                SubagentActivityInlineSummary(
                    activity: session.currentActivity,
                    activeSubagentCount: children.filter(\.isActive).count
                )
            } else {
                Text(session.currentActivity)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: DynamicIslandSpacing.related)

            StateIndicator(state: session.state, size: 12)
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

    private var accessibilityLabel: String {
        let identity = session.isSubagent
            ? "\(subagentLabel) subagent"
            : session.provider.displayName
        if let workflow = session.workflows.first {
            let active = children.filter(\.isActive).count
            let agents = active == 1 ? "1 active agent" : "\(active) active agents"
            return "\(identity), \(workflow.rowProgress), \(workflow.rowStage), \(agents), \(session.state.displayName)"
        }
        if let plan = session.plan, !plan.steps.isEmpty {
            return "\(identity), \(plan.rowProgress), \(plan.rowStage), \(session.state.displayName)"
        }
        if !children.isEmpty {
            let active = children.filter(\.isActive).count
            let subagents = active == 1 ? "1 active subagent" : "\(active) active subagents"
            return "\(identity), \(session.currentActivity), \(subagents), \(session.state.displayName)"
        }
        return "\(identity), \(session.currentActivity), \(session.state.displayName)"
    }
}

private struct SubagentActivityInlineSummary: View {
    let activity: String
    let activeSubagentCount: Int

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Text(activity)
                .lineLimit(1)

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text("\(activeSubagentCount) active")
            }
            .foregroundStyle(.white.opacity(0.46))
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }
}

private struct PlanInlineSummary: View {
    let plan: AgentPlan

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StepStatusStrip(steps: plan.steps)
            Text(plan.rowStage)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }
}

private struct ExecutionInlineSummary: View {
    let progress: String
    let stage: String
    let activeAgentCount: Int?

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Text(progress)
            Text(stage)
                .lineLimit(1)

            if let activeAgentCount {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                    Text("\(activeAgentCount) active")
                }
                .foregroundStyle(.white.opacity(0.46))
            }
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }
}

private extension AgentPlan {
    var rowProgress: String {
        "\(completedStepCount)/\(steps.count)"
    }

    var rowStage: String {
        let current = steps.first {
            $0.status == .inProgress || $0.status == .failed || $0.status == .blocked
        }
        if let current { return current.title }
        if steps.allSatisfy({ $0.status == .completed }), let final = steps.last { return final.title }
        if let pending = steps.first(where: { $0.status == .pending }) { return pending.title }
        return "Plan"
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
