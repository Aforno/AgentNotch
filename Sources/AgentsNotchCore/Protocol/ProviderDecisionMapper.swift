import Foundation

/// Converts a notch answer to the JSON that a provider hook writes to stdout.
public enum ProviderDecisionMapper {
    public static func data(
        provider: AgentProvider,
        payload: AgentHookPayload,
        reply: AgentReply
    ) -> Data {
        let object = jsonObject(provider: provider, payload: payload, reply: reply)
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}\n".utf8)
    }

    public static func jsonObject(
        provider: AgentProvider,
        payload: AgentHookPayload,
        reply: AgentReply
    ) -> [String: Any] {
        switch (provider, HookEventName(rawEventName: payload.hookEventName)) {
        case (.codex, .permissionRequest), (.claudeCode, .permissionRequest):
            return permissionOutput(reply: reply)
        case (.claudeCode, .preToolUse):
            switch payload.toolName.map(ProviderEventPolicy.toolIdentifier) {
            case "askuserquestion": return claudeQuestionOutput(payload: payload, reply: reply)
            case "exitplanmode": return claudePlanOutput(payload: payload, reply: reply)
            default: return [:]
            }
        case (.claudeCode, .elicitation):
            return claudeElicitationOutput(reply: reply)
        default:
            return [:]
        }
    }

    private static func permissionOutput(reply: AgentReply) -> [String: Any] {
        let allowed = reply.decision == .allow
        return [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionBody(allowed: allowed),
            ] as [String: Any],
        ]
    }

    private static func claudeQuestionOutput(payload: AgentHookPayload, reply: AgentReply) -> [String: Any] {
        let answers = validClaudeAnswers(payload: payload, reply: reply)
        let allowed = (reply.decision == .option || reply.decision == .allow) && answers != nil
        var output: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": allowed ? "allow" : "deny",
        ]
        if !allowed {
            output["permissionDecisionReason"] = "Denied from Agent Notch"
        }
        if allowed, var input = jsonObject(from: payload.toolInput), let answers {
            input["answers"] = answers.mapValues { $0.joined(separator: ", ") }
            output["updatedInput"] = input
        }
        return ["hookSpecificOutput": output]
    }

    private static func claudePlanOutput(payload: AgentHookPayload, reply: AgentReply) -> [String: Any] {
        let input = jsonObject(from: payload.toolInput)
        let allowed = reply.decision == .allow && input != nil
        var output: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": allowed ? "allow" : "deny",
        ]
        if allowed, let input {
            output["updatedInput"] = input
        } else {
            output["permissionDecisionReason"] = "Plan approval denied from Agent Notch"
        }
        return ["hookSpecificOutput": output]
    }

    /// The notch UI only sends deny/cancel for elicitation prompts today, so
    /// `accept` is reachable only from reply.sock clients that attach
    /// `content`. It stays because the wire protocol supports it and a future
    /// free-form input affordance can use it without a mapper change.
    private static func claudeElicitationOutput(reply: AgentReply) -> [String: Any] {
        let action: String = switch reply.decision {
        case .allow where jsonObject(from: reply.content) != nil: "accept"
        case .allow: "decline"
        case .deny: "decline"
        case .cancel: "cancel"
        case .option: "decline"
        }
        var output: [String: Any] = ["hookEventName": "Elicitation", "action": action]
        if action == "accept", let content = jsonObject(from: reply.content) {
            output["content"] = content
        }
        return ["hookSpecificOutput": output]
    }

    private static func validClaudeAnswers(
        payload: AgentHookPayload,
        reply: AgentReply
    ) -> [String: [String]]? {
        guard let answers = reply.answers,
              let questions = payload.toolInput?["questions"]?.arrayValue,
              !questions.isEmpty
        else { return nil }
        for questionValue in questions {
            guard let question = questionValue.objectValue,
                  let text = question["question"]?.stringValue,
                  let selected = answers[text],
                  !selected.isEmpty
            else { return nil }
            let labels = Set((question["options"]?.arrayValue ?? []).compactMap {
                $0.objectValue?["label"]?.stringValue ?? $0.stringValue
            })
            guard selected.allSatisfy(labels.contains) else { return nil }
            if question["multiSelect"]?.boolValue != true, selected.count != 1 { return nil }
        }
        return answers
    }

    private static func decisionBody(allowed: Bool) -> [String: Any] {
        if allowed {
            return ["behavior": "allow"]
        }
        return [
            "behavior": "deny",
            "message": "Denied from Agent Notch",
        ]
    }

    private static func jsonObject(from value: JSONValue?) -> [String: Any]? {
        guard let value, let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
