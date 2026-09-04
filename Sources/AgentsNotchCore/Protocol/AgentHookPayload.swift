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

/// Compatibility decoder for vendor hook JSON. Protocol v1 on the socket is
/// `AgentEvent` only — do not add another field alias without a mapper test.
public struct AgentHookPayload: Decodable, Sendable {
    public var sessionId: String
    public var transcriptPath: String?
    public var cwd: String
    public var workspaceRoot: String?
    public var hookEventName: String
    public var turnId: String?
    public var approvalsReviewer: String?
    public var prompt: String?
    public var source: String?
    public var reason: String?
    public var toolName: String?
    public var toolCallId: String?
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
        // Grok camelCase
        case sessionId, transcriptPath, cwd, workspaceRoot, hookEventName
        case turnId, approvalsReviewer, prompt, source, reason, status
        case toolName, toolUseId, toolCallId, toolInput, agentId, agentType, parentSessionId
        case description, lastAssistantMessage, notificationType
        case notificationMessage = "message"
        case promptResponse, error, timestamp, createdAt

        // Codex / Claude Code / Gemini CLI snake_case
        case sessionIdSnake = "session_id"
        case transcriptPathSnake = "transcript_path"
        case workspaceRootSnake = "workspace_root"
        case workspaceRootsSnake = "workspace_roots"
        case hookEventNameSnake = "hook_event_name"
        case turnIdSnake = "turn_id"
        case approvalsReviewerSnake = "approvals_reviewer"
        case toolNameSnake = "tool_name"
        case toolUseIdSnake = "tool_use_id"
        case toolCallIdSnake = "tool_call_id"
        case toolInputSnake = "tool_input"
        case agentIdSnake = "agent_id"
        case agentTypeSnake = "agent_type"
        case parentSessionIdSnake = "parent_session_id"
        case lastAssistantMessageSnake = "last_assistant_message"
        case notificationTypeSnake = "notification_type"
        case promptResponseSnake = "prompt_response"
        case errorMessageSnake = "error_message"
        case createdAtSnake = "created_at"

        // Cursor
        case conversationIdSnake = "conversation_id"
        case parentConversationIdSnake = "parent_conversation_id"

        // OpenCode / Claude aliases
        case subagentIdSnake = "subagent_id"
        case subagentTypeSnake = "subagent_type"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedSessionId = try values.decodeEitherIfPresent(
            String.self,
            forKey: .sessionId,
            or: .sessionIdSnake
        ) {
            sessionId = decodedSessionId
        } else {
            sessionId = try values.decode(String.self, forKey: .conversationIdSnake)
        }
        transcriptPath = try values.decodeEitherIfPresent(
            String.self,
            forKey: .transcriptPath,
            or: .transcriptPathSnake
        )
        workspaceRoot = try values.decodeEitherIfPresent(
            String.self,
            forKey: .workspaceRoot,
            or: .workspaceRootSnake
        )
        let workspaceRoots = try values.decodeIfPresent([String].self, forKey: .workspaceRootsSnake)
        // A present empty cwd (Cursor sends "") must not block workspace_root
        // / workspace_roots. decodeIfPresent only falls through on nil.
        cwd = try values.decodeIfPresent(String.self, forKey: .cwd)?.nonEmpty
            ?? workspaceRoot?.nonEmpty
            ?? workspaceRoots?.lazy.compactMap(\.nonEmpty).first
            ?? ""
        hookEventName = try values.decodeEither(
            String.self,
            forKey: .hookEventName,
            or: .hookEventNameSnake
        )
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
        let camelToolUseId = try values.decodeIfPresent(String.self, forKey: .toolUseId)?.nonEmpty
        let camelToolCallId = try values.decodeIfPresent(String.self, forKey: .toolCallId)?.nonEmpty
        let snakeToolUseId = try values.decodeIfPresent(String.self, forKey: .toolUseIdSnake)?.nonEmpty
        let snakeToolCallId = try values.decodeIfPresent(String.self, forKey: .toolCallIdSnake)?.nonEmpty
        toolCallId = camelToolUseId ?? camelToolCallId ?? snakeToolUseId ?? snakeToolCallId
        toolInput = try values.decodeEitherIfPresent(JSONValue.self, forKey: .toolInput, or: .toolInputSnake)
        agentId = try values.decodeEitherIfPresent(String.self, forKey: .agentId, or: .agentIdSnake)
            ?? values.decodeIfPresent(String.self, forKey: .subagentIdSnake)
        agentType = try values.decodeEitherIfPresent(String.self, forKey: .agentType, or: .agentTypeSnake)
            ?? values.decodeIfPresent(String.self, forKey: .subagentTypeSnake)
        parentSessionId = try values.decodeEitherIfPresent(
            String.self,
            forKey: .parentSessionId,
            or: .parentSessionIdSnake
        ) ?? values.decodeIfPresent(String.self, forKey: .parentConversationIdSnake)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        lastAssistantMessage = try values.decodeEitherIfPresent(
            String.self,
            forKey: .lastAssistantMessage,
            or: .lastAssistantMessageSnake
        )
        notificationType = try values.decodeEitherIfPresent(
            String.self,
            forKey: .notificationType,
            or: .notificationTypeSnake
        )
        notificationMessage = try values.decodeIfPresent(String.self, forKey: .notificationMessage)
        let promptResponse = try values.decodeEitherIfPresent(
            String.self,
            forKey: .promptResponse,
            or: .promptResponseSnake
        )
        lastAssistantMessage = lastAssistantMessage ?? promptResponse
        // OpenCode and others emit error as {"message":"..."}. A strict String
        // decode would throw and drop an otherwise-valid hook.
        error = values.decodeFlexibleStringIfPresent(forKey: .error)
            ?? values.decodeFlexibleStringIfPresent(forKey: .errorMessageSnake)
        timestamp = values.decodeFlexibleDateIfPresent(forKeys: [.timestamp, .createdAt, .createdAtSnake])
    }
}
