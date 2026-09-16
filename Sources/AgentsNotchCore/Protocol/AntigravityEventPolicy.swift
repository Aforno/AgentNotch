import Foundation

/// Antigravity hook quirks: nested `toolCall`, PascalCase and ACP snake_case
/// args, and PreInvocation 0 as session start.
public enum AntigravityEventPolicy {
    public static func enrich(_ payload: AgentHookPayload) -> ProviderHookEnrichment {
        var payload = payload
        normalizeToolName(&payload)
        normalizeToolInput(&payload)
        rewriteLifecycleEvent(&payload)
        return ProviderHookEnrichment(
            payload: payload,
            permissionRequestRequiresUserInput: true,
            preferredTask: nil,
            titleSource: nil,
            replaceExistingTask: false,
            workflowEvent: nil
        )
    }

    public static func isWaitingTool(_ toolName: String?) -> Bool {
        switch toolName.map(ProviderEventPolicy.toolIdentifier) {
        case "ask_question", "ask_permission": true
        default: false
        }
    }

    /// Stop requires `decision` (`stop` ends the turn; `continue`/`block`
    /// keep it running). `{}` fails protojson unmarshal and can hang Stop.
    public static func passiveResponse(eventName: String?) -> Data {
        switch HookEventName(rawEventName: eventName ?? "") {
        case .stop:
            Data("{\"decision\":\"stop\"}\n".utf8)
        default:
            Data("{}\n".utf8)
        }
    }

    public static func waitingActivity(for payload: AgentHookPayload) -> String {
        switch payload.toolName.map(ProviderEventPolicy.toolIdentifier) {
        case "ask_question":
            if let questions = payload.toolInput?["questions"]?.arrayValue {
                for question in questions {
                    if let text = question.objectValue?["question"]?.stringValue?.nonEmpty {
                        return ProviderEventPolicy.concise(text, limit: 90)
                    }
                }
            }
            return "Needs an answer"
        case "ask_permission":
            if let reason = payload.toolInput?["Reason"]?.stringValue?.nonEmpty
                ?? payload.toolInput?["reason"]?.stringValue?.nonEmpty
            {
                return ProviderEventPolicy.concise(reason, limit: 90)
            }
            return "Needs approval"
        default:
            return "Needs approval"
        }
    }

    /// ACP native tools (`client_create_file`, `client_edit_file`) are the
    /// same file mutations as the IDE's `write_to_file` / `replace_file_content`.
    private static func normalizeToolName(_ payload: inout AgentHookPayload) {
        switch payload.toolName.map(ProviderEventPolicy.toolIdentifier) {
        case "client_create_file", "client_write_file":
            payload.toolName = "write_to_file"
        case "client_edit_file":
            payload.toolName = "replace_file_content"
        case "client_view_file":
            payload.toolName = "view_file"
        default:
            break
        }
    }

    /// IDE tools send PascalCase (`TargetFile`, `AbsolutePath`, `CommandLine`).
    /// ACP native tools send snake_case (`target_file`, `absolute_path`).
    private static func normalizeToolInput(_ payload: inout AgentHookPayload) {
        guard var object = payload.toolInput?.objectValue else { return }
        if object["command"] == nil {
            object["command"] = object["CommandLine"] ?? object["command_line"]
        }
        if object["file_path"] == nil {
            for key in ["TargetFile", "target_file", "AbsolutePath", "absolute_path"] {
                if let file = object[key] {
                    object["file_path"] = file
                    break
                }
            }
        }
        payload.toolInput = .object(object)
    }

    private static func rewriteLifecycleEvent(_ payload: inout AgentHookPayload) {
        switch HookEventName(rawEventName: payload.hookEventName) {
        case .userPromptSubmit where payload.invocationNum == 0:
            payload.hookEventName = HookEventName.sessionStart.rawValue
        case .postToolUse where payload.error?.nonEmpty != nil:
            payload.hookEventName = HookEventName.postToolUseFailure.rawValue
        case .stop where isTurnLimit(payload.reason):
            payload.hookEventName = HookEventName.stopCancelled.rawValue
            payload.reason = "max_turns"
        default:
            break
        }
    }

    private static func isTurnLimit(_ reason: String?) -> Bool {
        reason?.replacingOccurrences(of: "-", with: "_").lowercased() == "max_steps_exceeded"
    }
}
