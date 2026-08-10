import AgentsNotchCore
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let subagents: [AgentSession]

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

            if let attention = groupAttentionSession {
                AttentionInlineSummary(session: attention)
            } else if let workflow = session.workflows.first {
                ExecutionInlineSummary(
                    progress: workflow.rowProgress,
                    stage: workflow.rowStage,
                    activeAgentCount: subagents.filter(\.isActive).count
                )
            } else if let plan = session.plan, !plan.steps.isEmpty {
                PlanInlineSummary(plan: plan)
            } else if !subagents.isEmpty {
                SubagentActivityInlineSummary(
                    activity: session.currentActivity,
                    activeSubagentCount: subagents.filter(\.isActive).count
                )
            } else {
                Text(session.currentActivity)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)
            }

            Spacer(minLength: DynamicIslandSpacing.related)

            StateIndicator(state: groupState, size: 12)
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .frame(height: DynamicIslandSpacing.rowHeight, alignment: .center)
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
        if let attention = groupAttentionSession {
            return "\(identity), \(attention.currentActivity), \(groupState.displayName)"
        }
        if let workflow = session.workflows.first {
            let active = subagents.filter(\.isActive).count
            let agents = active == 1 ? "1 active agent" : "\(active) active agents"
            return "\(identity), \(workflow.rowProgress), \(workflow.rowStage), \(agents), \(groupState.displayName)"
        }
        if let plan = session.plan, !plan.steps.isEmpty {
            return "\(identity), \(plan.rowProgress), \(plan.rowStage), \(groupState.displayName)"
        }
        if !subagents.isEmpty {
            let active = subagents.filter(\.isActive).count
            let subagents = active == 1 ? "1 active subagent" : "\(active) active subagents"
            return "\(identity), \(session.currentActivity), \(subagents), \(groupState.displayName)"
        }
        return "\(identity), \(session.currentActivity), \(groupState.displayName)"
    }

    private var groupAttentionSession: AgentSession? {
        ([session] + subagents)
            .filter { $0.state == .waitingForUser }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    private var groupState: AgentState {
        if groupAttentionSession != nil { return .waitingForUser }
        if session.state == .failed || subagents.contains(where: { $0.state == .failed }) { return .failed }
        return session.state
    }
}

private struct AttentionInlineSummary: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
            Text(label)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.orange)
    }

    private var label: String {
        guard let role = session.agentRole else { return session.currentActivity }
        let name = role
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .capitalized
        return "\(name) needs input"
    }
}

private struct SubagentActivityInlineSummary: View {
    let activity: String
    let activeSubagentCount: Int

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Text(activity)
                .lineLimit(1)

            ActiveAgentCountView(count: activeSubagentCount)
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
                .fixedSize(horizontal: true, vertical: false)
            Text(stage)
                .lineLimit(1)

            if let activeAgentCount {
                ActiveAgentCountView(count: activeAgentCount)
            }
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(.white.opacity(0.68))
        .lineLimit(1)
    }
}

private struct ActiveAgentCountView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
            Text("\(count) active")
        }
        .foregroundStyle(.white.opacity(0.46))
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }
}

enum AgentRowPresentation {
    static let maximumVisibleSteps = 6

    static func currentStep(in steps: [AgentStep]) -> AgentStep? {
        for status in [
            AgentStepStatus.inProgress,
            .failed,
            .blocked,
            .pending,
        ] {
            if let step = steps.first(where: { $0.status == status }) {
                return step
            }
        }
        return steps.last
    }

    static func visibleSteps(in steps: [AgentStep]) -> [AgentStep] {
        guard steps.count > maximumVisibleSteps else { return steps }
        guard let current = currentStep(in: steps),
              let currentIndex = steps.firstIndex(where: { $0.id == current.id })
        else {
            return Array(steps.suffix(maximumVisibleSteps))
        }

        let maximumStart = steps.count - maximumVisibleSteps
        let start = min(max(currentIndex - maximumVisibleSteps + 1, 0), maximumStart)
        return Array(steps[start..<(start + maximumVisibleSteps)])
    }
}

private extension AgentPlan {
    var rowProgress: String {
        "\(completedStepCount)/\(steps.count)"
    }

    var rowStage: String {
        if isComplete { return "Plan complete" }
        return AgentRowPresentation.currentStep(in: steps)?.title ?? "Plan"
    }
}

private extension AgentWorkflow {
    var rowProgress: String {
        guard !steps.isEmpty else { return status.displayName }
        let completed = steps.filter { $0.status == .completed }.count
        return "\(completed)/\(steps.count)"
    }

    var rowStage: String {
        AgentRowPresentation.currentStep(in: steps)?.title ?? status.displayName
    }
}

private struct StepStatusStrip: View {
    let steps: [AgentStep]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AgentRowPresentation.visibleSteps(in: steps)) { step in
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
