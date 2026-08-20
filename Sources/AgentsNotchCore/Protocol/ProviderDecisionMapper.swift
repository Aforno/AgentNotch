import Foundation

/// Maps a notch click onto the JSON body each provider's hook stdout expects.
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
        let eventName = HookEventName.metadataName(for: payload.hookEventName)
        let allowed = reply.decision != .deny
        switch HookEventName(rawEventName: payload.hookEventName) {
        case .preToolUse:
            return preToolUseOutput(eventName: eventName, allowed: allowed, reply: reply, payload: payload)
        case .elicitation:
            return [
                "hookSpecificOutput": [
                    "hookEventName": eventName,
                    "decision": decisionBody(allowed: allowed),
                ] as [String: Any],
            ]
        default:
            return permissionOutput(
                provider: provider,
                eventName: eventName,
                allowed: allowed
            )
        }
    }

    private static func permissionOutput(
        provider: AgentProvider,
        eventName: String,
        allowed: Bool
    ) -> [String: Any] {
        _ = provider
        return [
            "hookSpecificOutput": [
                "hookEventName": eventName,
                "decision": decisionBody(allowed: allowed),
            ] as [String: Any],
        ]
    }

    private static func preToolUseOutput(
        eventName: String,
        allowed: Bool,
        reply: AgentReply,
        payload: AgentHookPayload
    ) -> [String: Any] {
        var output: [String: Any] = [
            "hookEventName": eventName,
            "permissionDecision": allowed ? "allow" : "deny",
        ]
        if !allowed {
            output["permissionDecisionReason"] = "Denied from Agents Notch"
        }
        if allowed, let optionId = reply.optionId {
            output["permissionDecisionReason"] = "Selected \(optionId)"
            if var input = jsonObject(from: payload.toolInput) {
                input["agentsNotchSelectedOptionId"] = optionId
                output["updatedInput"] = input
            }
        }
        return ["hookSpecificOutput": output]
    }

    private static func decisionBody(allowed: Bool) -> [String: Any] {
        if allowed {
            return ["behavior": "allow"]
        }
        return [
            "behavior": "deny",
            "message": "Denied from Agents Notch",
        ]
    }

    private static func jsonObject(from value: JSONValue?) -> [String: Any]? {
        guard let value, let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }
}
