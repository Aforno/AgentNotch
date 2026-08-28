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
                        .font(NotchWindowFont.footnoteEmphasis)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)

                    PlanStatusStrip(steps: plan.steps)

                    Text(headline)
                        .font(NotchWindowFont.captionEmphasis)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: DynamicIslandSpacing.tight)

                    Text("\(plan.completedStepCount)/\(plan.steps.count)")
                        .font(NotchWindowFont.mono)
                        .monospacedDigit()
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
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
        if plan.isComplete { return "Plan complete" }
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
                    .fill(StepStatusStyle.color(for: step.status))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: stripWidth, height: 5)
        .accessibilityHidden(true)
    }

    private var stripWidth: CGFloat {
        min(max(CGFloat(steps.count) * 18, 18), 64)
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
                            .font(NotchWindowFont.captionEmphasis)
                            .foregroundStyle(NotchWindowPalette.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Text(workflow.status.displayName)
                            .font(NotchWindowFont.footnoteEmphasis)
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
        case .pending, .running: NotchWindowPalette.tertiaryText
        }
    }
}

struct AgentRelationshipsView: View {
    let parent: AgentSession?
    let children: [AgentSession]
    let onSelect: (String) -> Void

    var body: some View {
        if parent != nil || !children.isEmpty {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.tight) {
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
                        label: AgentRowPresentation.formattedRole(child.agentRole),
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
                    .font(NotchWindowFont.footnoteEmphasis)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(NotchWindowFont.footnoteEmphasis)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                    Text(session.currentActivity)
                        .font(NotchWindowFont.footnote)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                StateIndicator(state: session.state, size: 7)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(NotchWindowPalette.quaternaryText)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchRowButtonStyle(inset: -6))
    }
}

private struct AgentStepRow: View {
    let step: AgentStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DynamicIslandSpacing.related) {
            Image(systemName: StepStatusStyle.systemImage(for: step.status))
                .font(NotchWindowFont.footnoteEmphasis)
                .foregroundStyle(StepStatusStyle.color(for: step.status))
                .frame(width: 12)
            Text(step.title)
                .font(NotchWindowFont.footnote)
                .foregroundStyle(
                    step.status == .completed
                        ? NotchWindowPalette.tertiaryText
                        : NotchWindowPalette.secondaryText
                )
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title), \(step.status.displayName)")
    }
}

private extension View {
    func executionCard() -> some View {
        padding(DynamicIslandSpacing.standard)
            .notchPanel(cornerRadius: 9)
    }
}
