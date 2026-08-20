import Foundation

/// Codex plan snapshots and goal-tool workflow updates.
public enum CodexEventPolicy {
    public static func planSnapshot(
        from payload: AgentHookPayload,
        tool: String,
        now: Date
    ) -> AgentPlan? {
        guard tool == "update_plan",
              let values = payload.toolInput?["plan"]?.arrayValue
        else { return nil }

        let steps = values.enumerated().compactMap { index, value -> AgentStep? in
            guard let object = value.objectValue,
                  let title = object["step"]?.stringValue?.nonEmpty
            else { return nil }
            return AgentStep(
                id: "plan-step-\(index)",
                title: title,
                status: stepStatus(from: object["status"]?.stringValue)
            )
        }
        guard !steps.isEmpty else { return nil }
        return AgentPlan(
            title: payload.toolInput?["title"]?.stringValue?.nonEmpty,
            explanation: payload.toolInput?["explanation"]?.stringValue?.nonEmpty,
            steps: steps,
            updatedAt: now
        )
    }

    public static func workflowUpdate(
        from payload: AgentHookPayload,
        tool: String,
        sessionId: String
    ) -> AgentWorkflowUpdate? {
        let workflowID = payload.toolInput?["workflow_id"]?.stringValue?.nonEmpty
            ?? payload.toolInput?["id"]?.stringValue?.nonEmpty
            ?? "goal:\(sessionId)"
        switch tool {
        case "create_goal":
            return AgentWorkflowUpdate(
                id: workflowID,
                title: payload.toolInput?["objective"]?.stringValue?.nonEmpty ?? "Goal",
                status: .running
            )
        case "update_goal":
            let status = switch payload.toolInput?["status"]?.stringValue {
            case "complete", "completed": AgentWorkflowStatus.completed
            case "blocked": AgentWorkflowStatus.blocked
            case "failed": AgentWorkflowStatus.failed
            case "waiting": AgentWorkflowStatus.waiting
            default: AgentWorkflowStatus.running
            }
            return AgentWorkflowUpdate(id: workflowID, status: status)
        default:
            return nil
        }
    }

    private static func stepStatus(from value: String?) -> AgentStepStatus {
        switch value?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "in_progress", "running": .inProgress
        case "completed", "complete", "done": .completed
        case "failed": .failed
        case "blocked": .blocked
        default: .pending
        }
    }
}
