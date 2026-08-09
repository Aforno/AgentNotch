import AgentsNotchCore
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let children: [AgentSession]

    static let executionRowHeight: CGFloat = 62

    static func preferredHeight(for session: AgentSession, children: [AgentSession]) -> CGFloat {
        hasExecutionSummary(for: session, children: children)
            ? executionRowHeight
            : DynamicIslandSpacing.rowHeight
    }

    private static func hasExecutionSummary(for session: AgentSession, children: [AgentSession]) -> Bool {
        session.plan?.steps.isEmpty == false || !session.workflows.isEmpty || !children.isEmpty
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: DynamicIslandSpacing.standard) {
                    if session.isSubagent {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                            .frame(width: 10)
                    }

                    StateIndicator(state: session.state, size: 8)

                    ProviderIconView(provider: session.provider, size: 14)
                        .foregroundStyle(.white.opacity(0.9))

                    Text(session.isSubagent ? subagentLabel : session.provider.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: session.isSubagent ? 78 : 62, alignment: .leading)

                    Text(session.currentActivity)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    Spacer(minLength: DynamicIslandSpacing.related)

                    if session.needsAttention {
                        Image(systemName: session.state == .failed ? "xmark" : "exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(session.state == .failed ? .red : .orange)
                    } else {
                        Text(elapsed(from: session.startedAt, to: session.completedAt ?? context.date))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }

                if hasExecutionSummary {
                    AgentRowExecutionSummary(session: session, children: children)
                        .padding(.leading, session.isSubagent ? 42 : 32)
                }
            }
            .padding(.horizontal, DynamicIslandSpacing.outer)
            .frame(
                height: Self.preferredHeight(for: session, children: children),
                alignment: .center
            )
        }
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

    private var hasExecutionSummary: Bool {
        Self.hasExecutionSummary(for: session, children: children)
    }

    private var accessibilityLabel: String {
        let identity = session.isSubagent
            ? "\(subagentLabel) subagent"
            : session.provider.displayName
        return "\(identity), \(session.currentActivity), \(session.state.displayName)"
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(start)), 0)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h"
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

            if let workflow = session.workflows.first {
                HStack(spacing: 4) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text(workflowSummary(workflow))
                        .lineLimit(1)
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

    private func workflowSummary(_ workflow: AgentWorkflow) -> String {
        guard !workflow.steps.isEmpty else { return workflow.status.displayName }
        let completed = workflow.steps.filter { $0.status == .completed }.count
        return "\(completed)/\(workflow.steps.count) workflow"
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
