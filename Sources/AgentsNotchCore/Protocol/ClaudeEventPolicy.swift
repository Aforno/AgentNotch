import Foundation

/// Claude Code interactive tools, permission prompts, and approval copy.
public enum ClaudeEventPolicy {
    /// AskUserQuestion and ExitPlanMode pause for user input.
    public static func isInteractiveTool(_ toolName: String?) -> Bool {
        switch toolName.map(ProviderEventPolicy.toolIdentifier) {
        case "askuserquestion", "exitplanmode": true
        default: false
        }
    }

    public static func interactiveToolActivity(for payload: AgentHookPayload) -> String {
        switch payload.toolName.map(ProviderEventPolicy.toolIdentifier) {
        case "askuserquestion":
            if let questions = payload.toolInput?["questions"]?.arrayValue {
                for question in questions {
                    if let text = question.objectValue?["question"]?.stringValue?.nonEmpty {
                        return ProviderEventPolicy.concise(text, limit: 90)
                    }
                }
            }
            return "Needs an answer"
        case "exitplanmode":
            return "Needs plan approval"
        default:
            return "Needs approval"
        }
    }

    public static func isWaitingNotification(_ type: String?) -> Bool {
        switch type?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "permission_prompt", "idle_prompt", "agent_needs_input",
             "elicitation_dialog", "elicitation_url_dialog",
             "toolpermission", "tool_permission":
            return true
        default:
            return false
        }
    }

    public static func waitingNotificationActivity(for type: String?, message: String?) -> String {
        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return ProviderEventPolicy.concise(message, limit: 90)
        }
        switch type?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog",
             "toolpermission", "tool_permission":
            return "Needs approval"
        default:
            return "Waiting for input"
        }
    }

    public static func approvalActivity(for payload: AgentHookPayload) -> String {
        guard let toolName = payload.toolName else { return "Needs approval" }
        switch ProviderEventPolicy.toolIdentifier(toolName) {
        case "bash": return "Needs command approval"
        case "apply_patch", "edit", "write": return "Needs edit approval"
        case "askuserquestion": return "Needs an answer"
        case "exitplanmode": return "Needs plan approval"
        default: return "Needs approval for \(ProviderEventPolicy.displayTool(toolName))"
        }
    }
}
