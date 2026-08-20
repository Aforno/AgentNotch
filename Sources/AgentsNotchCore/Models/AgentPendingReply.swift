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

/// One Claude AskUserQuestion entry. Claude keys `updatedInput.answers` by the
/// original question text.
public struct AgentPromptQuestion: Codable, Hashable, Sendable, Identifiable {
    public var text: String
    public var header: String?
    public var options: [AgentPromptOption]
    public var allowsMultiple: Bool

    public var id: String { text }

    public init(text: String, header: String? = nil, options: [AgentPromptOption], allowsMultiple: Bool) {
        self.text = text
        self.header = header
        self.options = options
        self.allowsMultiple = allowsMultiple
    }
}

/// Buttons a provider will honor for this prompt.
public enum AgentReplyGrant: String, Codable, Sendable {
    case deny
    case allow
    case cancel
}

/// A waiting prompt and the ID used to match its reply to a hook process.
public struct AgentPendingReply: Codable, Hashable, Sendable, Identifiable {
    public var replyId: UUID
    public var kind: AgentPromptKind
    public var prompt: String
    public var detail: String?
    public var options: [AgentPromptOption]
    public var questions: [AgentPromptQuestion]?
    public var grants: [AgentReplyGrant]

    public var id: UUID { replyId }

    public init(
        replyId: UUID,
        kind: AgentPromptKind,
        prompt: String,
        detail: String? = nil,
        options: [AgentPromptOption] = [],
        questions: [AgentPromptQuestion] = [],
        grants: [AgentReplyGrant] = []
    ) {
        self.replyId = replyId
        self.kind = kind
        self.prompt = prompt
        self.detail = detail
        self.options = options
        self.questions = questions
        self.grants = grants
    }

    public var allowsAllow: Bool { grants.contains(.allow) }
    public var allowsDeny: Bool { grants.contains(.deny) }
    public var allowsCancel: Bool { grants.contains(.cancel) }
}

/// Decision written back to a blocked hook.
public enum AgentReplyDecision: String, Codable, Sendable {
    case deny
    case allow
    case option
    case cancel
}

public struct AgentReply: Codable, Hashable, Sendable {
    public var replyId: UUID
    public var decision: AgentReplyDecision
    public var optionId: String?
    public var answers: [String: [String]]?
    public var content: JSONValue?

    public init(
        replyId: UUID,
        decision: AgentReplyDecision,
        optionId: String? = nil,
        answers: [String: [String]]? = nil,
        content: JSONValue? = nil
    ) {
        self.replyId = replyId
        self.decision = decision
        self.optionId = optionId
        self.answers = answers
        self.content = content
    }

    public var isDeny: Bool { decision == .deny }
}

public struct AgentReplyHello: Codable, Sendable {
    public var replyId: UUID

    public init(replyId: UUID) {
        self.replyId = replyId
    }
}

public struct AgentReplyAcknowledgement: Codable, Sendable, Equatable {
    public var registered: Bool

    public init(registered: Bool = true) {
        self.registered = registered
    }
}

/// Defines which hooks can wait for a reply and how long they wait.
public enum AgentReplyPolicy {
    public static let waitSeconds = 120

    /// Claude `PreToolUse` matcher for the tools the notch can answer.
    /// Hook install and install verification must share this constant.
    public static let claudeInteractiveToolMatcher = "AskUserQuestion|ExitPlanMode"

    /// Claude `PreToolUse` matcher for tools that remain passive observers
    /// while Answer from the notch is enabled.
    public static let claudePassiveToolMatcher = "^(?!AskUserQuestion$|ExitPlanMode$).*"

    public static func waitsForAnswer(eventName: String, toolName: String? = nil) -> Bool {
        switch HookEventName(rawEventName: eventName) {
        case .permissionRequest, .elicitation:
            return true
        case .preToolUse:
            guard let toolName else { return false }
            let tool = ProviderEventPolicy.toolIdentifier(toolName)
            return tool == "askuserquestion" || tool == "exitplanmode"
        default:
            return false
        }
    }

    public static func canDecide(provider: AgentProvider) -> Bool {
        switch provider {
        case .codex, .claudeCode:
            true
        default:
            false
        }
    }
}
