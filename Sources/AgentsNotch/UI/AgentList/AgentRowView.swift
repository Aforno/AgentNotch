import AgentsNotchCore
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession
    let subagents: [AgentSession]
    @AppStorage(AppPreferences.Key.privacyModeEnabled) private var privacyModeEnabled = false

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.standard) {
            if session.isSubagent {
                Image(systemName: "arrow.turn.down.right")
                    .font(NotchWindowFont.footnoteEmphasis)
                    .foregroundStyle(NotchWindowPalette.quaternaryText)
                    .frame(width: 10)
            }

            ProviderIconView(provider: session.provider, size: 14)
                .foregroundStyle(NotchWindowPalette.primaryText)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DynamicIslandSpacing.related) {
                    if session.isSubagent {
                        RowChip(text: subagentLabel)
                    }

                    if !taskTitle.isEmpty {
                        Text(taskTitle)
                            .font(NotchWindowFont.rowTitle)
                            .foregroundStyle(NotchWindowPalette.primaryText)
                            .lineLimit(1)
                    }

                    // The project is the disambiguator when several agents run
                    // in similar repos, so it holds its width and lets the task
                    // title truncate instead.
                    if let projectChip {
                        RowChip(text: projectChip)
                            .layoutPriority(1)
                    }
                }

                if showsActivitySummary {
                    activitySummary
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: DynamicIslandSpacing.related)

            StateIndicator(state: groupState, size: 12)
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .frame(height: DynamicIslandSpacing.rowHeight, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var headline: String {
        AgentRowPresentation.headline(for: session, privacyModeEnabled: privacyModeEnabled)
    }

    private var taskTitle: String {
        AgentRowPresentation.taskTitle(for: session, privacyModeEnabled: privacyModeEnabled)
    }

    private var projectChip: String? {
        AgentRowPresentation.projectChip(for: session, privacyModeEnabled: privacyModeEnabled)
    }

    private var subagentLabel: String {
        AgentRowPresentation.formattedRole(session.agentRole)
    }

    @ViewBuilder
    private var activitySummary: some View {
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
                .font(NotchWindowFont.body)
                .foregroundStyle(NotchWindowPalette.secondaryText)
                .lineLimit(1)
        }
    }

    private var showsActivitySummary: Bool {
        if privacyModeEnabled { return false }
        if groupAttentionSession != nil { return true }
        if session.workflows.first != nil { return true }
        if let plan = session.plan, !plan.steps.isEmpty { return true }
        if !subagents.isEmpty { return true }
        return session.currentActivity != headline
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if session.isSubagent {
            parts.append("\(subagentLabel) subagent")
        }
        parts.append(session.provider.displayName)
        if !headline.isEmpty {
            parts.append(headline)
        }
        if privacyModeEnabled {
            parts.append(groupState.displayName)
            return parts.joined(separator: ", ")
        }
        if let attention = groupAttentionSession {
            parts.append(attention.currentActivity)
        } else if let workflow = session.workflows.first {
            let active = subagents.filter(\.isActive).count
            parts.append(workflow.rowProgress)
            parts.append(workflow.rowStage)
            parts.append(active == 1 ? "1 active agent" : "\(active) active agents")
        } else if let plan = session.plan, !plan.steps.isEmpty {
            parts.append(plan.rowProgress)
            parts.append(plan.rowStage)
        } else if !subagents.isEmpty {
            let active = subagents.filter(\.isActive).count
            parts.append(session.currentActivity)
            parts.append(active == 1 ? "1 active subagent" : "\(active) active subagents")
        } else if session.currentActivity != headline {
            parts.append(session.currentActivity)
        }
        parts.append(groupState.displayName)
        return parts.joined(separator: ", ")
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

private struct RowChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(NotchWindowFont.footnoteEmphasis)
            .foregroundStyle(NotchWindowPalette.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(NotchWindowPalette.raisedStrong, in: Capsule())
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 132, alignment: .leading)
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
        .font(NotchWindowFont.bodyEmphasis)
        .foregroundStyle(.orange)
    }

    private var label: String {
        guard session.agentRole != nil else { return session.currentActivity }
        return "\(AgentRowPresentation.formattedRole(session.agentRole)) needs input"
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
        .font(NotchWindowFont.body)
        .foregroundStyle(NotchWindowPalette.secondaryText)
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
        .font(NotchWindowFont.body)
        .foregroundStyle(NotchWindowPalette.secondaryText)
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
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
            Text(stage)
                .lineLimit(1)

            if let activeAgentCount {
                ActiveAgentCountView(count: activeAgentCount)
            }
        }
        .font(NotchWindowFont.body)
        .foregroundStyle(NotchWindowPalette.secondaryText)
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
        .foregroundStyle(NotchWindowPalette.tertiaryText)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }
}

enum AgentRowPresentation {
    static let maximumVisibleSteps = 6
    static func projectName(for session: AgentSession) -> String? {
        session.projectName
    }

    static func formattedRole(_ role: String?) -> String {
        let trimmed = role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Subagent" }
        return trimmed
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .capitalized
    }

    /// Combined single-line description. Still the source for accessibility and
    /// for deciding whether the activity line would just repeat the title.
    static func headline(for session: AgentSession, privacyModeEnabled: Bool) -> String {
        let project = projectName(for: session)
        if privacyModeEnabled {
            return project ?? "Private activity"
        }

        let task = AgentTaskTitle.displayable(session.task)
        if session.isSubagent {
            return task ?? ""
        }

        switch (task, project) {
        case let (task?, project?) where task != project:
            return "\(task) · \(project)"
        case let (task?, _):
            return task
        case let (nil, project?):
            return project
        case (nil, nil):
            return session.currentActivity
        }
    }

    static func taskTitle(for session: AgentSession, privacyModeEnabled: Bool) -> String {
        let project = projectName(for: session)
        if privacyModeEnabled {
            return project ?? "Private activity"
        }

        let task = AgentTaskTitle.displayable(session.task)
        if session.isSubagent {
            return task ?? ""
        }
        return task ?? project ?? session.currentActivity
    }

    /// The project pill, shown only when it adds information the task title does
    /// not already carry. Subagents inherit their parent's project.
    static func projectChip(for session: AgentSession, privacyModeEnabled: Bool) -> String? {
        guard !privacyModeEnabled, !session.isSubagent else { return nil }
        guard let project = projectName(for: session) else { return nil }
        guard let task = AgentTaskTitle.displayable(session.task), task != project else { return nil }
        return project
    }

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
                    .fill(StepStatusStyle.color(for: step.status))
                    .frame(width: 10, height: 4)
            }
        }
        .accessibilityHidden(true)
    }
}
