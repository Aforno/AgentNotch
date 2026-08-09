import AgentsNotchCore
import SwiftUI

struct AgentPlanProgressView: View {
    let plan: AgentPlan
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DynamicIslandSpacing.related) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)

                    PlanStatusStrip(steps: plan.steps)

                    Text(headline)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)

                    Spacer(minLength: DynamicIslandSpacing.tight)

                    Text("\(plan.completedStepCount)/\(plan.steps.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.34))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plan, \(headline), \(plan.completedStepCount) of \(plan.steps.count) steps complete")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                    ForEach(plan.steps) { step in
                        AgentStepRow(step: step)
                    }
                }
                .padding(.top, DynamicIslandSpacing.standard)
                .padding(.leading, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .executionCard()
    }

    private var headline: String {
        if let title = plan.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return plan.steps.first(where: { $0.status == .inProgress })?.title
            ?? plan.steps.first(where: { $0.status == .pending })?.title
            ?? plan.steps.last?.title
            ?? "Plan"
    }
}

private struct PlanStatusStrip: View {
    let steps: [AgentStep]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(steps) { step in
                Capsule()
                    .fill(color(for: step.status))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: stripWidth, height: 4)
        .accessibilityHidden(true)
    }

    private var stripWidth: CGFloat {
        min(max(CGFloat(steps.count) * 18, 18), 64)
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

struct AgentWorkflowsView: View {
    let workflows: [AgentWorkflow]

    var body: some View {
        VStack(alignment: .leading, spacing: DynamicIslandSpacing.standard) {
            ForEach(workflows.prefix(2)) { workflow in
                VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                    HStack {
                        Label(workflow.title, systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                        Spacer()
                        Text(workflow.status.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(workflowStatusColor(workflow.status))
                    }

                    ForEach(workflow.steps.prefix(4)) { step in
                        AgentStepRow(step: step)
                    }
                }
                .executionCard()
            }
        }
    }

    private func workflowStatusColor(_ status: AgentWorkflowStatus) -> Color {
        switch status {
        case .completed: .green
        case .failed: .red
        case .blocked, .waiting: .orange
        case .pending, .running: .white.opacity(0.46)
        }
    }
}

struct AgentRelationshipsView: View {
    let parent: AgentSession?
    let children: [AgentSession]
    let onSelect: (String) -> Void

    var body: some View {
        if parent != nil || !children.isEmpty {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                if let parent {
                    relationshipButton(
                        session: parent,
                        label: "Parent agent",
                        systemImage: "arrow.turn.up.left"
                    )
                }
                ForEach(children) { child in
                    relationshipButton(
                        session: child,
                        label: child.agentRole?
                            .replacingOccurrences(of: "_", with: " ")
                            .replacingOccurrences(of: "-", with: " ")
                            .replacingOccurrences(of: ":", with: " ")
                            .capitalized ?? "Subagent",
                        systemImage: "arrow.turn.down.right"
                    )
                }
            }
            .executionCard()
        }
    }

    private func relationshipButton(
        session: AgentSession,
        label: String,
        systemImage: String
    ) -> some View {
        Button {
            onSelect(session.id)
        } label: {
            HStack(spacing: DynamicIslandSpacing.related) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.34))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(session.currentActivity)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
                StateIndicator(state: session.state, size: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.24))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AgentStepRow: View {
    let step: AgentStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DynamicIslandSpacing.related) {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 12)
            Text(step.title)
                .font(.system(size: 10))
                .foregroundStyle(step.status == .completed ? .white.opacity(0.36) : .white.opacity(0.64))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title), \(step.status.displayName)")
    }

    private var iconName: String {
        switch step.status {
        case .pending: "circle"
        case .inProgress: "circle.fill"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .blocked: "exclamationmark"
        }
    }

    private var iconColor: Color {
        switch step.status {
        case .pending: .white.opacity(0.24)
        case .inProgress: .blue
        case .completed: .green
        case .failed: .red
        case .blocked: .orange
        }
    }
}

private extension View {
    func executionCard() -> some View {
        padding(DynamicIslandSpacing.standard)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }
}
