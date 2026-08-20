import Foundation

/// Why a session is waiting. Drives which notch actions are valid.
public enum AgentPromptKind: String, Codable, Sendable {
    case permission
    case question
    case plan
    case elicitation
}

/// A single choice on a waiting prompt.
public struct AgentPromptOption: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Buttons a provider will honor for this prompt.
public enum AgentReplyGrant: String, Codable, Sendable {
    case deny
    case once
    case allow
    case session
}

/// Display-only prompt plus the id the hook process is blocked on.
public struct AgentPendingReply: Codable, Hashable, Sendable, Identifiable {
    public var replyId: UUID
    public var kind: AgentPromptKind
    public var prompt: String
    public var detail: String?
    public var options: [AgentPromptOption]
    public var grants: [AgentReplyGrant]

    public var id: UUID { replyId }

    public init(
        replyId: UUID,
        kind: AgentPromptKind,
        prompt: String,
        detail: String? = nil,
        options: [AgentPromptOption] = [],
        grants: [AgentReplyGrant] = []
    ) {
        self.replyId = replyId
        self.kind = kind
        self.prompt = prompt
        self.detail = detail
        self.options = options
        self.grants = grants
    }

    public var allowsOnce: Bool { grants.contains(.once) }
    public var allowsAllow: Bool { grants.contains(.allow) || grants.contains(.session) }
    public var allowsDeny: Bool { grants.contains(.deny) }
}

/// Decision written back to a blocked hook.
public enum AgentReplyDecision: String, Codable, Sendable {
    case deny
    case allow
    case once
    case option
}

public struct AgentReply: Codable, Hashable, Sendable {
    public var replyId: UUID
    public var decision: AgentReplyDecision
    public var optionId: String?

    public init(replyId: UUID, decision: AgentReplyDecision, optionId: String? = nil) {
        self.replyId = replyId
        self.decision = decision
        self.optionId = optionId
    }

    public var isDeny: Bool { decision == .deny }
}

public struct AgentReplyHello: Codable, Sendable {
    public var replyId: UUID

    public init(replyId: UUID) {
        self.replyId = replyId
    }
}

/// Shared wait budget for permission hooks and the reply socket.
public enum AgentReplyPolicy {
    public static let waitSeconds = 120

    public static func waitsForAnswer(eventName: String) -> Bool {
        switch HookEventName(rawEventName: eventName) {
        case .permissionRequest, .preToolUse, .elicitation:
            true
        default:
            false
        }
    }

    public static func canDecide(provider: AgentProvider) -> Bool {
        switch provider {
        case .codex, .claudeCode, .grok, .geminiCLI:
            true
        default:
            false
        }
    }
}
