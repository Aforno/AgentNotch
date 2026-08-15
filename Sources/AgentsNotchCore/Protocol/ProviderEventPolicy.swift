import Foundation

/// Per-provider skip and enrich rules. `AgentHookEventMapper` stays a switch
/// on `HookEventName`; vendor quirks live here.
public enum ProviderEventPolicy {
    public static func shouldMapSessionStart(
        provider: AgentProvider,
        source: String?
    ) -> Bool {
        switch provider {
        case .grok:
            // Grok emits SessionStart for non-agent commands such as
            // `grok --version`, then exits without a matching SessionEnd.
            return false
        default:
            return !isLifecycleReentry(source: source)
        }
    }

    public static func remapsParentScopedSubagent(
        provider: AgentProvider,
        payload: AgentHookPayload,
        parentSessionId: String?
    ) -> Bool {
        provider == .grok
            && payload.agentId?.nonEmpty == nil
            && parentSessionId == nil
    }

    public static func isInteractiveTool(_ toolName: String?) -> Bool {
        ClaudeCode.isInteractiveTool(toolName)
    }

    public static func interactiveToolActivity(for payload: AgentHookPayload) -> String {
        ClaudeCode.interactiveToolActivity(for: payload)
    }

    public static func isWaitingNotification(_ type: String?) -> Bool {
        ClaudeCode.isWaitingNotification(type)
    }

    public static func waitingNotificationActivity(for type: String?, message: String?) -> String {
        ClaudeCode.waitingNotificationActivity(for: type, message: message)
    }

    public static func approvalActivity(for payload: AgentHookPayload) -> String {
        ClaudeCode.approvalActivity(for: payload)
    }

    public static func toolPresentation(
        payload: AgentHookPayload,
        completed: Bool,
        sessionId: String,
        now: Date
    ) -> ToolPresentation {
        let rawTool = payload.toolName ?? "tool"
        let tool = normalizedToolName(rawTool)
        let semanticTool = toolIdentifier(tool)
        let command = payload.toolInput?["command"]?.stringValue
        let isEdit = ["apply_patch", "edit", "write", "multiedit", "notebookedit", "patch"]
            .contains(semanticTool)
        let file = isEdit
            ? payload.toolInput?["file_path"]?.stringValue
                ?? payload.toolInput?["filePath"]?.stringValue
                ?? payload.toolInput?["path"]?.stringValue
                ?? changedFile(from: command)
            : nil

        return ToolPresentation(
            type: completed ? .toolCompleted : (isEdit ? .fileChanged : .toolStarted),
            state: completed ? .running : (isEdit ? .editing : .executingTool),
            activity: toolActivity(
                semanticTool: semanticTool,
                tool: tool,
                completed: completed,
                isEdit: isEdit,
                file: file,
                command: command
            ),
            file: file,
            rawTool: rawTool,
            plan: Codex.planSnapshot(from: payload, tool: semanticTool, now: now),
            workflowUpdate: Codex.workflowUpdate(
                from: payload,
                tool: semanticTool,
                sessionId: sessionId
            )
        )
    }

    public struct ToolPresentation: Sendable {
        public let type: AgentEventType
        public let state: AgentState
        public let activity: String
        public let file: String?
        public let rawTool: String
        public let plan: AgentPlan?
        public let workflowUpdate: AgentWorkflowUpdate?
    }

    public enum Codex {
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
    }

    public enum ClaudeCode {
        /// AskUserQuestion and ExitPlanMode pause for user input.
        public static func isInteractiveTool(_ toolName: String?) -> Bool {
            switch toolName.map(toolIdentifier) {
            case "askuserquestion", "exitplanmode": true
            default: false
            }
        }

        public static func interactiveToolActivity(for payload: AgentHookPayload) -> String {
            switch payload.toolName.map(toolIdentifier) {
            case "askuserquestion":
                if let questions = payload.toolInput?["questions"]?.arrayValue {
                    for question in questions {
                        if let text = question.objectValue?["question"]?.stringValue?.nonEmpty {
                            return concise(text, limit: 90)
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
                return concise(message, limit: 90)
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
            switch toolIdentifier(toolName) {
            case "bash": return "Needs command approval"
            case "apply_patch", "edit", "write": return "Needs edit approval"
            case "askuserquestion": return "Needs an answer"
            case "exitplanmode": return "Needs plan approval"
            default: return "Needs approval for \(displayTool(toolName))"
            }
        }
    }

    public enum Grok {
        public static func shouldPublishWorkflowState(_ payload: AgentHookPayload) -> Bool {
            switch HookEventName(rawEventName: payload.hookEventName) {
            case .subagentStart, .subagentStop, .sessionEnd, .stop:
                return true
            default:
                return payload.toolName?.lowercased() == "workflow"
            }
        }

        public static func shouldResolveSessionContext(_ payload: AgentHookPayload) -> Bool {
            if shouldPublishWorkflowState(payload) { return true }
            if HookEventName(rawEventName: payload.hookEventName) == .userPromptSubmit {
                return true
            }
            if payload.parentSessionId?.nonEmpty != nil { return false }
            return true
        }
    }

    private static func toolActivity(
        semanticTool: String,
        tool: String,
        completed: Bool,
        isEdit: Bool,
        file: String?,
        command: String?
    ) -> String {
        if semanticTool == "update_plan" {
            return completed ? "Plan updated" : "Updating plan"
        }
        if semanticTool == "create_goal" {
            return completed ? "Workflow started" : "Starting workflow"
        }
        if semanticTool == "update_goal" {
            return completed ? "Workflow updated" : "Updating workflow"
        }
        if completed {
            return isEdit ? "Finished editing" : "Finished \(displayTool(tool))"
        }
        if isEdit {
            return file.map { "Editing \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "Editing files"
        }
        if tool == "Bash", let command {
            return "Running \(concise(command, limit: 76))"
        }
        return "Using \(displayTool(tool))"
    }

    /// SessionStart sources that re-enter an existing session rather than start one.
    private static func isLifecycleReentry(source: String?) -> Bool {
        guard let source else { return false }
        switch source.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "resume", "compact", "compaction":
            return true
        default:
            return false
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

    fileprivate static func toolIdentifier(_ tool: String) -> String {
        tool.split(separator: "__").last.map(String.init)?.lowercased() ?? tool.lowercased()
    }

    private static func normalizedToolName(_ toolName: String) -> String {
        switch toolName.lowercased() {
        case "bash", "shell", "run_shell_command", "run_terminal_command": "Bash"
        case "edit", "search_replace": "Edit"
        case "write": "Write"
        default: toolName
        }
    }

    fileprivate static func displayTool(_ tool: String) -> String {
        if tool == "Bash" { return "command" }
        if tool.hasPrefix("mcp__") {
            return tool.split(separator: "__").last.map(String.init) ?? "tool"
        }
        return tool.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    public static func concise(_ text: String, limit: Int) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard line.count > limit else { return line }
        return String(line.prefix(limit - 1)) + "…"
    }

    private static func changedFile(from patch: String?) -> String? {
        guard let patch else { return nil }
        let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        for line in patch.split(whereSeparator: \.isNewline).map(String.init) {
            for prefix in prefixes where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }
}
