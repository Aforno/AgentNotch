import Foundation

/// Canonical provider-hook lifecycle names, plus the aliases each vendor emits.
/// `AgentHookPayload` stays a compatibility decoder; this type is the only
/// place that maps those spellings onto protocol events.
public enum HookEventName: String, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case permissionRequest = "PermissionRequest"
    case permissionDenied = "PermissionDenied"
    case elicitation = "Elicitation"
    case elicitationResult = "ElicitationResult"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case sessionEnd = "SessionEnd"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"

    public init?(rawEventName: String) {
        switch Self.normalizedKey(rawEventName) {
        case "sessionstart":
            self = .sessionStart
        case "userpromptsubmit", "beforesubmitprompt", "beforeagent":
            self = .userPromptSubmit
        case "pretooluse", "beforetool":
            self = .preToolUse
        case "posttooluse", "aftertool":
            self = .postToolUse
        case "posttoolusefailure":
            self = .postToolUseFailure
        case "permissionrequest":
            self = .permissionRequest
        case "permissiondenied":
            self = .permissionDenied
        case "elicitation":
            self = .elicitation
        case "elicitationresult":
            self = .elicitationResult
        case "notification":
            self = .notification
        case "stop", "afteragent":
            self = .stop
        case "stopfailure":
            self = .stopFailure
        case "sessionend":
            self = .sessionEnd
        case "subagentstart":
            self = .subagentStart
        case "subagentstop", "subagentend":
            self = .subagentStop
        default:
            return nil
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .stop, .stopFailure, .sessionEnd:
            true
        default:
            false
        }
    }

    public var resumesSession: Bool {
        self == .userPromptSubmit
    }

    /// Prefer the canonical name only when the provider sent an alias
    /// (BeforeAgent → UserPromptSubmit). Unaliased names keep their original
    /// spelling for diagnostics.
    public static func metadataName(for rawEventName: String) -> String {
        guard let name = Self(rawEventName: rawEventName) else { return rawEventName }
        return normalizedKey(rawEventName) == normalizedKey(name.rawValue)
            ? rawEventName
            : name.rawValue
    }

    private static func normalizedKey(_ eventName: String) -> String {
        eventName
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}
