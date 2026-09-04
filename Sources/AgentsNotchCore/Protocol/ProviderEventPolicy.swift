import Foundation

/// Shared event semantics. `AgentHookEventMapper` stays a switch on
/// `HookEventName`; provider quirks live in the per-provider policy types.
public enum ProviderEventPolicy {
    public static func shouldMapSessionStart(
        provider: AgentProvider,
        source: String?
    ) -> Bool {
        switch provider {
        case .grok:
            return GrokEventPolicy.shouldMapSessionStart
        default:
            return !isLifecycleReentry(source: source)
        }
    }

    public static func isInteractiveTool(_ toolName: String?) -> Bool {
        ClaudeEventPolicy.isInteractiveTool(toolName)
    }

    public static func interactiveToolActivity(for payload: AgentHookPayload) -> String {
        ClaudeEventPolicy.interactiveToolActivity(for: payload)
    }

    public static func isWaitingNotification(_ type: String?) -> Bool {
        ClaudeEventPolicy.isWaitingNotification(type)
    }

    public static func waitingNotificationActivity(for type: String?, message: String?) -> String {
        ClaudeEventPolicy.waitingNotificationActivity(for: type, message: message)
    }

    public static func approvalActivity(for payload: AgentHookPayload) -> String {
        ClaudeEventPolicy.approvalActivity(for: payload)
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
            plan: CodexEventPolicy.planSnapshot(from: payload, tool: semanticTool, now: now),
            workflowUpdate: CodexEventPolicy.workflowUpdate(
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

    static func toolIdentifier(_ tool: String) -> String {
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

    static func displayTool(_ tool: String) -> String {
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
