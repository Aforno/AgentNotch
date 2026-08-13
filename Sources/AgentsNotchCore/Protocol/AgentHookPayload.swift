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

private extension KeyedDecodingContainer {
    func decodeEither<T: Decodable>(
        _ type: T.Type,
        forKey first: Key,
        or second: Key
    ) throws -> T {
        // contains() is true for JSON null. decode() then throws valueNotFound
        // and never tries the snake_case alias (e.g. hookEventName:null with
        // a valid hook_event_name).
        if let value = try? decodeIfPresent(type, forKey: first) { return value }
        return try decode(type, forKey: second)
    }

    func decodeEitherIfPresent<T: Decodable>(
        _ type: T.Type,
        forKey first: Key,
        or second: Key
    ) throws -> T? {
        if let value = try? decodeIfPresent(type, forKey: first) { return value }
        return try decodeIfPresent(type, forKey: second)
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) -> String? {
        guard contains(key) else { return nil }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        guard let value = try? decode(JSONValue.self, forKey: key) else { return nil }
        if let string = value.stringValue { return string }
        if let message = value.objectValue?["message"]?.stringValue { return message }
        return value.objectValue?["error"]?.stringValue
    }

    func decodeFlexibleDateIfPresent(forKeys keys: [Key]) -> Date? {
        for key in keys where contains(key) {
            if let value = try? decode(String.self, forKey: key) {
                if let date = try? Date(
                    value,
                    strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                ) {
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
