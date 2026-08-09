import Foundation

public enum AgentHookInputError: LocalizedError, Equatable {
    case inputTooLarge

    public var errorDescription: String? {
        "Hook input exceeds the 1 MiB safety limit."
    }
}

public enum AgentHookInput {
    public static let maximumBytes = 1_048_576

    public static func decode(_ data: Data) throws -> AgentHookPayload {
        guard data.count <= maximumBytes else { throw AgentHookInputError.inputTooLarge }
        return try JSONDecoder().decode(AgentHookPayload.self, from: data)
    }
}

public struct AgentHookPayload: Decodable, Sendable {
    public var sessionId: String
    public var transcriptPath: String?
    public var cwd: String
    public var workspaceRoot: String?
    public var hookEventName: String
    public var model: String?
    public var turnId: String?
    public var prompt: String?
    public var source: String?
    public var reason: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var agentId: String?
    public var agentType: String?
    public var parentSessionId: String?
    public var description: String?
    public var lastAssistantMessage: String?
    public var notificationType: String?
    public var error: String?
    public var timestamp: Date?

    private enum CodingKeys: String, CodingKey {
        case sessionId, sessionIdSnake = "session_id"
        case transcriptPath, transcriptPathSnake = "transcript_path"
        case cwd, workspaceRoot, workspaceRootSnake = "workspace_root"
        case hookEventName, hookEventNameSnake = "hook_event_name"
        case model
        case turnId, turnIdSnake = "turn_id"
        case prompt, source, reason
        case toolName, toolNameSnake = "tool_name"
        case toolInput, toolInputSnake = "tool_input"
        case agentId, agentIdSnake = "agent_id"
        case agentType, agentTypeSnake = "agent_type"
        case parentSessionId, parentSessionIdSnake = "parent_session_id"
        case description
        case lastAssistantMessage, lastAssistantMessageSnake = "last_assistant_message"
        case notificationType, notificationTypeSnake = "notification_type"
        case error
        case timestamp, createdAt, createdAtSnake = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try values.decodeEither(String.self, forKey: .sessionId, or: .sessionIdSnake)
        transcriptPath = try values.decodeEitherIfPresent(String.self, forKey: .transcriptPath, or: .transcriptPathSnake)
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        workspaceRoot = try values.decodeEitherIfPresent(String.self, forKey: .workspaceRoot, or: .workspaceRootSnake)
        hookEventName = try values.decodeEither(String.self, forKey: .hookEventName, or: .hookEventNameSnake)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        turnId = try values.decodeEitherIfPresent(String.self, forKey: .turnId, or: .turnIdSnake)
        prompt = try values.decodeIfPresent(String.self, forKey: .prompt)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
        toolName = try values.decodeEitherIfPresent(String.self, forKey: .toolName, or: .toolNameSnake)
        toolInput = try values.decodeEitherIfPresent(JSONValue.self, forKey: .toolInput, or: .toolInputSnake)
        agentId = try values.decodeEitherIfPresent(String.self, forKey: .agentId, or: .agentIdSnake)
        agentType = try values.decodeEitherIfPresent(String.self, forKey: .agentType, or: .agentTypeSnake)
        parentSessionId = try values.decodeEitherIfPresent(String.self, forKey: .parentSessionId, or: .parentSessionIdSnake)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        lastAssistantMessage = try values.decodeEitherIfPresent(String.self, forKey: .lastAssistantMessage, or: .lastAssistantMessageSnake)
        notificationType = try values.decodeEitherIfPresent(String.self, forKey: .notificationType, or: .notificationTypeSnake)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        timestamp = values.decodeFlexibleDateIfPresent(forKeys: [.timestamp, .createdAt, .createdAtSnake])
    }
}

public enum AgentHookEventMapper {
    public static func map(
        _ payload: AgentHookPayload,
        provider: AgentProvider,
        now: Date = Date()
    ) -> AgentEvent? {
        let nativeSessionId: String
        if let agentId = payload.agentId, !agentId.isEmpty {
            nativeSessionId = "\(payload.sessionId):\(agentId)"
        } else {
            nativeSessionId = payload.sessionId
        }
        let sessionId = "\(provider.rawValue):\(nativeSessionId)"
        let nativeParentSessionId = payload.parentSessionId?.nonEmpty
            ?? (payload.agentId?.isEmpty == false ? payload.sessionId : nil)
        let parentSessionId = nativeParentSessionId.map { "\(provider.rawValue):\($0)" }

        let baseMetadata = [
            "model": payload.model,
            "turnId": payload.turnId,
            "hookEvent": payload.hookEventName,
        ].compactMapValues { $0 }

        let event: AgentEvent?
        switch normalizedEventName(payload.hookEventName) {
        case "SessionStart":
            if provider == .grok {
                // Grok emits SessionStart while initializing non-agent commands
                // such as `grok --version`, then exits without a prompt or a
                // matching SessionEnd. Wait for the first turn event so those
                // lifecycle-only probes never become permanently active agents.
                event = nil
            } else if isLifecycleReentry(source: payload.source) {
                // Providers re-emit SessionStart on resume/compact. Mapping those
                // to .starting with a cwd-basename task would clobber the
                // prompt-derived title and regress in-progress sessions.
                event = nil
            } else {
                event = AgentEvent(
                    type: .started,
                    sessionId: sessionId,
                    provider: provider,
                    task: repositoryName(from: payload.cwd, provider: provider),
                    activity: "Session started",
                    state: .starting,
                    timestamp: now,
                    workingDirectory: payload.cwd.nonEmpty,
                    metadata: baseMetadata
                )
            }

        case "UserPromptSubmit":
            let task = payload.prompt.map { concise($0, limit: 140) }
            event = AgentEvent(
                type: .activity,
                sessionId: sessionId,
                provider: provider,
                task: task,
                activity: "Thinking",
                state: .thinking,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "PreToolUse":
            event = toolEvent(payload, provider: provider, sessionId: sessionId, completed: false, now: now, metadata: baseMetadata)

        case "PostToolUse":
            event = toolEvent(payload, provider: provider, sessionId: sessionId, completed: true, now: now, metadata: baseMetadata)

        case "PostToolUseFailure":
            event = AgentEvent(
                type: .toolCompleted,
                sessionId: sessionId,
                provider: provider,
                activity: payload.error.map { "Tool failed: \(concise($0, limit: 76))" } ?? "Tool failed",
                state: .running,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "PermissionRequest":
            event = AgentEvent(
                type: .waiting,
                sessionId: sessionId,
                provider: provider,
                activity: approvalActivity(for: payload),
                state: .waitingForUser,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "PermissionDenied":
            event = AgentEvent(
                type: .activity,
                sessionId: sessionId,
                provider: provider,
                activity: "Tool permission denied",
                state: .running,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "Notification" where isWaitingNotification(payload.notificationType):
            event = AgentEvent(
                type: .waiting,
                sessionId: sessionId,
                provider: provider,
                activity: waitingNotificationActivity(for: payload.notificationType),
                state: .waitingForUser,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "Stop":
            event = AgentEvent(
                type: .completed,
                sessionId: sessionId,
                provider: provider,
                activity: completionActivity(from: payload.lastAssistantMessage),
                state: .completed,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "StopFailure":
            event = AgentEvent(
                type: .failed,
                sessionId: sessionId,
                provider: provider,
                activity: payload.error.map { concise($0, limit: 90) } ?? "Turn failed",
                state: .failed,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "SessionEnd":
            event = AgentEvent(
                type: .completed,
                sessionId: sessionId,
                provider: provider,
                activity: "Session ended",
                state: .completed,
                timestamp: now,
                workingDirectory: payload.cwd.nonEmpty,
                metadata: baseMetadata
            )

        case "SubagentStart":
            if provider == .grok, payload.agentId?.nonEmpty == nil, parentSessionId == nil {
                // Grok fires this hook in the parent and puts the parent's ID in
                // sessionId. The child later emits its own lifecycle/tool hooks.
                // Keep the parent alive without turning it into a fake child row.
                event = AgentEvent(
                    type: .activity,
                    sessionId: sessionId,
                    provider: provider,
                    activity: "Running subagents",
                    state: .running,
                    timestamp: now,
                    workingDirectory: payload.cwd.nonEmpty,
                    metadata: baseMetadata
                )
            } else {
                let role = payload.description?.nonEmpty
                    ?? payload.agentType?.nonEmpty.map { $0.capitalized }
                event = AgentEvent(
                    type: .started,
                    sessionId: sessionId,
                    provider: provider,
                    task: role.map { "\($0) subagent" } ?? "\(provider.displayName) subagent",
                    activity: "Subagent started",
                    state: .starting,
                    timestamp: now,
                    workingDirectory: payload.cwd.nonEmpty,
                    metadata: baseMetadata
                )
            }

        case "SubagentStop":
            if provider == .grok, payload.agentId?.nonEmpty == nil, parentSessionId == nil {
                // Mirror SubagentStart: Grok parent-scoped SubagentStop uses the
                // parent sessionId without agent_id. Completing the parent would
                // end the turn while other subagents may still be live.
                event = AgentEvent(
                    type: .activity,
                    sessionId: sessionId,
                    provider: provider,
                    activity: "Subagent completed",
                    state: .running,
                    timestamp: now,
                    workingDirectory: payload.cwd.nonEmpty,
                    metadata: baseMetadata
                )
            } else {
                event = AgentEvent(
                    type: .completed,
                    sessionId: sessionId,
                    provider: provider,
                    activity: "Subagent completed",
                    state: .completed,
                    timestamp: now,
                    workingDirectory: payload.cwd.nonEmpty,
                    metadata: baseMetadata
                )
            }

        default:
            event = nil
        }

        guard var event else { return nil }
        let eventTimestamp = payload.timestamp ?? now
        event.timestamp = eventTimestamp
        event.plan?.updatedAt = eventTimestamp
        event.parentSessionId = parentSessionId
        event.agentRole = payload.description?.nonEmpty ?? payload.agentType
        return event
    }

    private static func toolEvent(
        _ payload: AgentHookPayload,
        provider: AgentProvider,
        sessionId: String,
        completed: Bool,
        now: Date,
        metadata: [String: String]
    ) -> AgentEvent {
        let rawTool = payload.toolName ?? "tool"
        let tool = normalizedToolName(rawTool)
        let semanticTool = toolIdentifier(tool)
        let command = payload.toolInput?["command"]?.stringValue
        let isEdit = ["apply_patch", "Edit", "Write", "MultiEdit", "NotebookEdit"].contains(tool)
        let file = isEdit
            ? payload.toolInput?["file_path"]?.stringValue
                ?? payload.toolInput?["path"]?.stringValue
                ?? changedFile(from: command)
            : nil

        let type: AgentEventType = completed ? .toolCompleted : (isEdit ? .fileChanged : .toolStarted)
        let state: AgentState = completed ? .running : (isEdit ? .editing : .executingTool)
        let activity: String
        if semanticTool == "update_plan" {
            activity = completed ? "Plan updated" : "Updating plan"
        } else if semanticTool == "create_goal" {
            activity = completed ? "Workflow started" : "Starting workflow"
        } else if semanticTool == "update_goal" {
            activity = completed ? "Workflow updated" : "Updating workflow"
        } else if completed {
            activity = isEdit ? "Finished editing" : "Finished \(displayTool(tool))"
        } else if isEdit {
            activity = file.map { "Editing \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "Editing files"
        } else if tool == "Bash", let command {
            activity = "Running \(concise(command, limit: 76))"
        } else {
            activity = "Using \(displayTool(tool))"
        }

        return AgentEvent(
            type: type,
            sessionId: sessionId,
            provider: provider,
            activity: activity,
            state: state,
            timestamp: now,
            workingDirectory: payload.cwd.nonEmpty,
            file: file,
            metadata: metadata.merging(["tool": rawTool], uniquingKeysWith: { _, new in new }),
            plan: planSnapshot(from: payload, tool: semanticTool, now: now),
            workflowUpdate: workflowUpdate(from: payload, tool: semanticTool, sessionId: sessionId)
        )
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

    /// Claude Code Notification matchers that mean the agent is blocked on the user.
    private static func isWaitingNotification(_ type: String?) -> Bool {
        switch type?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog":
            return true
        default:
            return false
        }
    }

    private static func waitingNotificationActivity(for type: String?) -> String {
        switch type?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "permission_prompt", "elicitation_dialog":
            return "Needs approval"
        default:
            return "Waiting for input"
        }
    }

    private static func planSnapshot(from payload: AgentHookPayload, tool: String, now: Date) -> AgentPlan? {
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

    private static func workflowUpdate(
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

    private static func toolIdentifier(_ tool: String) -> String {
        tool.split(separator: "__").last.map(String.init)?.lowercased() ?? tool.lowercased()
    }

    private static func normalizedEventName(_ eventName: String) -> String {
        switch eventName.replacingOccurrences(of: "_", with: "").lowercased() {
        case "sessionstart": "SessionStart"
        case "userpromptsubmit": "UserPromptSubmit"
        case "pretooluse": "PreToolUse"
        case "posttooluse": "PostToolUse"
        case "posttoolusefailure": "PostToolUseFailure"
        case "permissionrequest": "PermissionRequest"
        case "permissiondenied": "PermissionDenied"
        case "notification": "Notification"
        case "stop": "Stop"
        case "stopfailure": "StopFailure"
        case "sessionend": "SessionEnd"
        case "subagentstart": "SubagentStart"
        case "subagentstop", "subagentend": "SubagentStop"
        default: eventName
        }
    }

    private static func normalizedToolName(_ toolName: String) -> String {
        switch toolName {
        case "run_terminal_command": "Bash"
        case "search_replace": "Edit"
        default: toolName
        }
    }

    private static func approvalActivity(for payload: AgentHookPayload) -> String {
        switch payload.toolName {
        case "Bash": "Needs command approval"
        case "apply_patch", "Edit", "Write": "Needs edit approval"
        case let tool?: "Needs approval for \(displayTool(tool))"
        case nil: "Needs approval"
        }
    }

    private static func completionActivity(from message: String?) -> String {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Task completed"
        }
        return concise(message, limit: 90)
    }

    private static func repositoryName(from cwd: String, provider: AgentProvider) -> String {
        URL(fileURLWithPath: cwd).lastPathComponent.nonEmpty ?? "\(provider.displayName) session"
    }

    private static func displayTool(_ tool: String) -> String {
        if tool == "Bash" { return "command" }
        if tool.hasPrefix("mcp__") {
            return tool.split(separator: "__").last.map(String.init) ?? "tool"
        }
        return tool.replacingOccurrences(of: "_", with: " ").lowercased()
    }

    private static func concise(_ text: String, limit: Int) -> String {
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

public typealias CodexHookPayload = AgentHookPayload

public enum CodexHookEventMapper {
    public static func map(_ payload: CodexHookPayload, now: Date = Date()) -> AgentEvent? {
        AgentHookEventMapper.map(payload, provider: .codex, now: now)
    }
}

private extension KeyedDecodingContainer {
    func decodeEither<T: Decodable>(_ type: T.Type, forKey first: Key, or second: Key) throws -> T {
        if contains(first) { return try decode(type, forKey: first) }
        return try decode(type, forKey: second)
    }

    func decodeEitherIfPresent<T: Decodable>(_ type: T.Type, forKey first: Key, or second: Key) throws -> T? {
        if contains(first) { return try decodeIfPresent(type, forKey: first) }
        return try decodeIfPresent(type, forKey: second)
    }

    func decodeFlexibleDateIfPresent(forKeys keys: [Key]) -> Date? {
        for key in keys where contains(key) {
            if let value = try? decode(String.self, forKey: key) {
                if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                    return date
                }
                if let date = try? Date(value, strategy: Date.ISO8601FormatStyle()) {
                    return date
                }
            }
            if let value = try? decode(Double.self, forKey: key) {
                let seconds = value > 10_000_000_000 ? value / 1_000 : value
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
