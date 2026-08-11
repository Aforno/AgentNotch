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
    public var approvalsReviewer: String?
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
    public var notificationMessage: String?
    public var error: String?
    public var timestamp: Date?

    private enum CodingKeys: String, CodingKey {
        case sessionId, sessionIdSnake = "session_id"
        case conversationIdSnake = "conversation_id"
        case transcriptPath, transcriptPathSnake = "transcript_path"
        case cwd, workspaceRoot, workspaceRootSnake = "workspace_root", workspaceRootsSnake = "workspace_roots"
        case hookEventName, hookEventNameSnake = "hook_event_name"
        case model
        case turnId, turnIdSnake = "turn_id"
        case approvalsReviewer, approvalsReviewerSnake = "approvals_reviewer"
        case prompt, source, reason, status
        case toolName, toolNameSnake = "tool_name"
        case toolInput, toolInputSnake = "tool_input"
        case agentId, agentIdSnake = "agent_id", subagentIdSnake = "subagent_id"
        case agentType, agentTypeSnake = "agent_type", subagentTypeSnake = "subagent_type"
        case parentSessionId, parentSessionIdSnake = "parent_session_id", parentConversationIdSnake = "parent_conversation_id"
        case description
        case lastAssistantMessage, lastAssistantMessageSnake = "last_assistant_message"
        case notificationType, notificationTypeSnake = "notification_type"
        case notificationMessage = "message"
        case promptResponse, promptResponseSnake = "prompt_response"
        case error, errorMessageSnake = "error_message"
        case timestamp, createdAt, createdAtSnake = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedSessionId = try values.decodeEitherIfPresent(String.self, forKey: .sessionId, or: .sessionIdSnake) {
            sessionId = decodedSessionId
        } else {
            sessionId = try values.decode(String.self, forKey: .conversationIdSnake)
        }
        transcriptPath = try values.decodeEitherIfPresent(String.self, forKey: .transcriptPath, or: .transcriptPathSnake)
        workspaceRoot = try values.decodeEitherIfPresent(String.self, forKey: .workspaceRoot, or: .workspaceRootSnake)
        let workspaceRoots = try values.decodeIfPresent([String].self, forKey: .workspaceRootsSnake)
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd)
            ?? workspaceRoot
            ?? workspaceRoots?.first
            ?? ""
        hookEventName = try values.decodeEither(String.self, forKey: .hookEventName, or: .hookEventNameSnake)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        turnId = try values.decodeEitherIfPresent(String.self, forKey: .turnId, or: .turnIdSnake)
        approvalsReviewer = try values.decodeEitherIfPresent(
            String.self,
            forKey: .approvalsReviewer,
            or: .approvalsReviewerSnake
        )
        prompt = try values.decodeIfPresent(String.self, forKey: .prompt)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
            ?? values.decodeIfPresent(String.self, forKey: .status)
        toolName = try values.decodeEitherIfPresent(String.self, forKey: .toolName, or: .toolNameSnake)
        toolInput = try values.decodeEitherIfPresent(JSONValue.self, forKey: .toolInput, or: .toolInputSnake)
        agentId = try values.decodeEitherIfPresent(String.self, forKey: .agentId, or: .agentIdSnake)
            ?? values.decodeIfPresent(String.self, forKey: .subagentIdSnake)
        agentType = try values.decodeEitherIfPresent(String.self, forKey: .agentType, or: .agentTypeSnake)
            ?? values.decodeIfPresent(String.self, forKey: .subagentTypeSnake)
        parentSessionId = try values.decodeEitherIfPresent(String.self, forKey: .parentSessionId, or: .parentSessionIdSnake)
            ?? values.decodeIfPresent(String.self, forKey: .parentConversationIdSnake)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        lastAssistantMessage = try values.decodeEitherIfPresent(String.self, forKey: .lastAssistantMessage, or: .lastAssistantMessageSnake)
        notificationType = try values.decodeEitherIfPresent(String.self, forKey: .notificationType, or: .notificationTypeSnake)
        notificationMessage = try values.decodeIfPresent(String.self, forKey: .notificationMessage)
        let promptResponse = try values.decodeEitherIfPresent(String.self, forKey: .promptResponse, or: .promptResponseSnake)
        lastAssistantMessage = lastAssistantMessage ?? promptResponse
        error = try values.decodeIfPresent(String.self, forKey: .error)
            ?? values.decodeIfPresent(String.self, forKey: .errorMessageSnake)
        timestamp = values.decodeFlexibleDateIfPresent(forKeys: [.timestamp, .createdAt, .createdAtSnake])
    }
}

public enum AgentHookEventMapper {
    public static func map(
        _ payload: AgentHookPayload,
        provider: AgentProvider,
        permissionRequestRequiresUserInput: Bool = true,
        now: Date = Date()
    ) -> AgentEvent? {
        let context = mappingContext(for: payload, provider: provider, now: now)
        guard var event = mappedEvent(
            payload,
            permissionRequestRequiresUserInput: permissionRequestRequiresUserInput,
            context: context
        ) else { return nil }

        let eventTimestamp = payload.timestamp ?? now
        event.timestamp = eventTimestamp
        event.plan?.updatedAt = eventTimestamp
        event.parentSessionId = context.parentSessionId
        event.agentRole = payload.description?.nonEmpty ?? payload.agentType
        return event
    }

    private struct MappingContext {
        let provider: AgentProvider
        let sessionId: String
        let parentSessionId: String?
        let now: Date
        let workingDirectory: String?
        let metadata: [String: String]

        func event(
            type: AgentEventType,
            task: String? = nil,
            activity: String,
            state: AgentState
        ) -> AgentEvent {
            AgentEvent(
                type: type,
                sessionId: sessionId,
                provider: provider,
                task: task,
                activity: activity,
                state: state,
                timestamp: now,
                workingDirectory: workingDirectory,
                metadata: metadata
            )
        }
    }

    private static func mappingContext(
        for payload: AgentHookPayload,
        provider: AgentProvider,
        now: Date
    ) -> MappingContext {
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

        let metadata = [
            "model": payload.model,
            "turnId": payload.turnId,
            // Store the canonical lifecycle name when the provider uses an
            // alias (e.g. Gemini BeforeAgent → UserPromptSubmit) so session
            // resume and other hookEvent gates stay provider-neutral.
            "hookEvent": metadataHookEventName(payload.hookEventName),
        ].compactMapValues { $0 }

        return MappingContext(
            provider: provider,
            sessionId: sessionId,
            parentSessionId: parentSessionId,
            now: now,
            workingDirectory: payload.cwd.nonEmpty,
            metadata: metadata
        )
    }

    private static func mappedEvent(
        _ payload: AgentHookPayload,
        permissionRequestRequiresUserInput: Bool,
        context: MappingContext
    ) -> AgentEvent? {
        switch normalizedEventName(payload.hookEventName) {
        case "SessionStart":
            return sessionStartEvent(payload, context: context)

        case "UserPromptSubmit":
            return context.event(
                type: .activity,
                task: payload.prompt.map { concise($0, limit: 140) },
                activity: "Thinking",
                state: .thinking
            )

        case "PreToolUse":
            return toolEvent(payload, completed: false, context: context)

        case "PostToolUse":
            return toolEvent(payload, completed: true, context: context)

        case "PostToolUseFailure":
            return context.event(
                type: .toolCompleted,
                activity: payload.error.map { "Tool failed: \(concise($0, limit: 76))" } ?? "Tool failed",
                state: .running
            )

        case "PermissionRequest" where permissionRequestRequiresUserInput:
            return context.event(
                type: .waiting,
                activity: approvalActivity(for: payload),
                state: .waitingForUser
            )

        case "PermissionRequest":
            return nil

        case "PermissionDenied":
            return context.event(
                type: .activity,
                activity: "Tool permission denied",
                state: .running
            )

        case "Notification" where isWaitingNotification(payload.notificationType):
            return context.event(
                type: .waiting,
                activity: waitingNotificationActivity(
                    for: payload.notificationType,
                    message: payload.notificationMessage
                ),
                state: .waitingForUser
            )

        case "Stop":
            return terminalEvent(
                payload,
                successActivity: completionActivity(from: payload.lastAssistantMessage),
                failureActivity: "Task failed",
                context: context
            )

        case "StopFailure":
            return context.event(
                type: .failed,
                activity: payload.error.map { concise($0, limit: 90) } ?? "Turn failed",
                state: .failed
            )

        case "SessionEnd":
            return terminalEvent(
                payload,
                successActivity: "Session ended",
                failureActivity: "Session failed",
                context: context
            )

        case "SubagentStart":
            return subagentEvent(payload, started: true, context: context)

        case "SubagentStop":
            return subagentEvent(payload, started: false, context: context)

        default:
            return nil
        }
    }

    private static func sessionStartEvent(
        _ payload: AgentHookPayload,
        context: MappingContext
    ) -> AgentEvent? {
        // Grok emits SessionStart while initializing non-agent commands such as
        // `grok --version`, then exits without a prompt or matching SessionEnd.
        guard context.provider != .grok else { return nil }
        // Providers re-emit SessionStart on resume/compact. Treating those as a
        // new start would clobber the prompt-derived title and active state.
        guard !isLifecycleReentry(source: payload.source) else { return nil }
        return context.event(
            type: .started,
            task: repositoryName(from: payload.cwd, provider: context.provider),
            activity: "Session started",
            state: .starting
        )
    }

    private static func terminalEvent(
        _ payload: AgentHookPayload,
        successActivity: String,
        failureActivity: String,
        context: MappingContext
    ) -> AgentEvent {
        if isFailureReason(payload.reason) {
            return context.event(
                type: .failed,
                activity: payload.error.map { concise($0, limit: 90) } ?? failureActivity,
                state: .failed
            )
        }
        return context.event(
            type: .completed,
            activity: successActivity,
            state: .completed
        )
    }

    private static func subagentEvent(
        _ payload: AgentHookPayload,
        started: Bool,
        context: MappingContext
    ) -> AgentEvent {
        let isParentScopedGrokEvent = context.provider == .grok
            && payload.agentId?.nonEmpty == nil
            && context.parentSessionId == nil
        if isParentScopedGrokEvent {
            // Grok fires these hooks in the parent and puts the parent's ID in
            // sessionId. Keep the parent active without creating a fake child or
            // completing the parent while other children may still be live.
            return context.event(
                type: .activity,
                activity: started ? "Running subagents" : "Subagent completed",
                state: .running
            )
        }
        if started {
            let role = payload.description?.nonEmpty
                ?? payload.agentType?.nonEmpty.map { $0.capitalized }
            return context.event(
                type: .started,
                task: role.map { "\($0) subagent" } ?? "\(context.provider.displayName) subagent",
                activity: "Subagent started",
                state: .starting
            )
        }
        return context.event(
            type: .completed,
            activity: "Subagent completed",
            state: .completed
        )
    }

    private static func toolEvent(
        _ payload: AgentHookPayload,
        completed: Bool,
        context: MappingContext
    ) -> AgentEvent {
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
            sessionId: context.sessionId,
            provider: context.provider,
            activity: activity,
            state: state,
            timestamp: context.now,
            workingDirectory: context.workingDirectory,
            file: file,
            metadata: context.metadata.merging(["tool": rawTool], uniquingKeysWith: { _, new in new }),
            plan: planSnapshot(from: payload, tool: semanticTool, now: context.now),
            workflowUpdate: workflowUpdate(from: payload, tool: semanticTool, sessionId: context.sessionId)
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

    private static func isFailureReason(_ reason: String?) -> Bool {
        switch reason?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "error", "failed", "failure": true
        default: false
        }
    }

    /// Claude Code Notification matchers that mean the agent is blocked on the user.
    private static func isWaitingNotification(_ type: String?) -> Bool {
        switch type?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "permission_prompt", "idle_prompt", "agent_needs_input", "elicitation_dialog", "toolpermission", "tool_permission":
            return true
        default:
            return false
        }
    }

    private static func waitingNotificationActivity(for type: String?, message: String?) -> String {
        if let message = message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return concise(message, limit: 90)
        }
        switch type?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "permission_prompt", "elicitation_dialog", "toolpermission", "tool_permission":
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
        case "beforesubmitprompt": "UserPromptSubmit"
        case "beforeagent": "UserPromptSubmit"
        case "pretooluse": "PreToolUse"
        case "beforetool": "PreToolUse"
        case "posttooluse": "PostToolUse"
        case "aftertool": "PostToolUse"
        case "posttoolusefailure": "PostToolUseFailure"
        case "permissionrequest": "PermissionRequest"
        case "permissiondenied": "PermissionDenied"
        case "notification": "Notification"
        case "stop": "Stop"
        case "afteragent": "Stop"
        case "stopfailure": "StopFailure"
        case "sessionend": "SessionEnd"
        case "subagentstart": "SubagentStart"
        case "subagentstop", "subagentend": "SubagentStop"
        default: eventName
        }
    }

    /// Prefer the canonical lifecycle name only when the provider sent an
    /// alias that maps to a different event (BeforeAgent → UserPromptSubmit).
    /// Unaliased names keep their original spelling for diagnostics.
    private static func metadataHookEventName(_ eventName: String) -> String {
        let normalized = normalizedEventName(eventName)
        let rawKey = eventName.replacingOccurrences(of: "_", with: "").lowercased()
        let normalizedKey = normalized.replacingOccurrences(of: "_", with: "").lowercased()
        return rawKey == normalizedKey ? eventName : normalized
    }

    private static func normalizedToolName(_ toolName: String) -> String {
        switch toolName.lowercased() {
        case "bash", "shell", "run_shell_command", "run_terminal_command": "Bash"
        case "edit", "search_replace": "Edit"
        case "write": "Write"
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
    public static func map(
        _ payload: CodexHookPayload,
        permissionRequestRequiresUserInput: Bool = true,
        now: Date = Date()
    ) -> AgentEvent? {
        AgentHookEventMapper.map(
            payload,
            provider: .codex,
            permissionRequestRequiresUserInput: permissionRequestRequiresUserInput,
            now: now
        )
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
