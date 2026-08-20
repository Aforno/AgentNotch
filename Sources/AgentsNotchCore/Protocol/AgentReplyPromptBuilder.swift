import Foundation

/// Builds the notch prompt from a provider hook payload. Display only; the
/// hook process attaches `replyId` when it is willing to wait for a click.
public enum AgentReplyPromptBuilder {
    public static func make(
        payload: AgentHookPayload,
        replyId: UUID
    ) -> AgentPendingReply? {
        if ProviderEventPolicy.isInteractiveTool(payload.toolName) {
            return interactivePrompt(payload: payload, replyId: replyId)
        }
        if HookEventName(rawEventName: payload.hookEventName) == .permissionRequest {
            return permissionPrompt(payload: payload, replyId: replyId)
        }
        if HookEventName(rawEventName: payload.hookEventName) == .elicitation
            || ProviderEventPolicy.isWaitingNotification(payload.notificationType)
        {
            return elicitationPrompt(payload: payload, replyId: replyId)
        }
        return permissionPrompt(payload: payload, replyId: replyId)
    }

    private static func interactivePrompt(
        payload: AgentHookPayload,
        replyId: UUID
    ) -> AgentPendingReply {
        switch payload.toolName.map(ProviderEventPolicy.toolIdentifier) {
        case "askuserquestion":
            let questions = payload.toolInput?["questions"]?.arrayValue ?? []
            let first = questions.first?.objectValue
            let prompt = first?["question"]?.stringValue?.nonEmpty
                ?? first?["header"]?.stringValue?.nonEmpty
                ?? "Needs an answer"
            let options = options(from: first?["options"])
            return AgentPendingReply(
                replyId: replyId,
                kind: .question,
                prompt: ProviderEventPolicy.concise(prompt, limit: 160),
                detail: nil,
                options: Array(options.prefix(6)),
                grants: options.isEmpty ? [.deny, .allow] : []
            )
        case "exitplanmode":
            let plan = payload.toolInput?["plan"]?.stringValue
                ?? payload.toolInput?["allowedPrompts"]?.stringValue
            return AgentPendingReply(
                replyId: replyId,
                kind: .plan,
                prompt: "Exit plan mode and start editing?",
                detail: plan.map { ProviderEventPolicy.concise($0, limit: 400) },
                grants: [.deny, .allow]
            )
        default:
            return permissionPrompt(payload: payload, replyId: replyId)
        }
    }

    private static func permissionPrompt(
        payload: AgentHookPayload,
        replyId: UUID
    ) -> AgentPendingReply {
        let command = payload.toolInput?["command"]?.stringValue?.nonEmpty
        let file = payload.toolInput?["file_path"]?.stringValue
            ?? payload.toolInput?["filePath"]?.stringValue
            ?? payload.toolInput?["path"]?.stringValue
        let tool = payload.toolName.map(ProviderEventPolicy.displayTool)
        let detail = command
            ?? file
            ?? tool.map { "Allow \($0)?" }
        let prompt = command == nil
            ? ProviderEventPolicy.approvalActivity(for: payload)
            : "Allow this command?"
        return AgentPendingReply(
            replyId: replyId,
            kind: .permission,
            prompt: prompt,
            detail: detail.map { ProviderEventPolicy.concise($0, limit: 400) },
            grants: [.deny, .once, .allow]
        )
    }

    private static func elicitationPrompt(
        payload: AgentHookPayload,
        replyId: UUID
    ) -> AgentPendingReply {
        let message = payload.notificationMessage?.nonEmpty
            ?? payload.prompt?.nonEmpty
            ?? "Needs approval"
        return AgentPendingReply(
            replyId: replyId,
            kind: .elicitation,
            prompt: ProviderEventPolicy.concise(message, limit: 160),
            grants: [.deny, .allow]
        )
    }

    private static func options(from value: JSONValue?) -> [AgentPromptOption] {
        guard let values = value?.arrayValue else { return [] }
        return values.enumerated().compactMap { index, entry in
            if let label = entry.stringValue?.nonEmpty {
                return AgentPromptOption(id: "option-\(index)", label: label)
            }
            let object = entry.objectValue
            let label = object?["label"]?.stringValue?.nonEmpty
                ?? object?["title"]?.stringValue?.nonEmpty
                ?? object?["text"]?.stringValue?.nonEmpty
            guard let label else { return nil }
            let id = object?["id"]?.stringValue?.nonEmpty ?? "option-\(index)"
            return AgentPromptOption(id: id, label: ProviderEventPolicy.concise(label, limit: 48))
        }
    }
}
