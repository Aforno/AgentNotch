import Foundation

public enum AgentReplyPromptBuilder {
    public static func make(
        payload: AgentHookPayload,
        replyId: UUID
    ) -> AgentPendingReply? {
        if ClaudeEventPolicy.isInteractiveTool(payload.toolName) {
            return interactivePrompt(payload: payload, replyId: replyId)
        }
        if HookEventName(rawEventName: payload.hookEventName) == .elicitation
            || ClaudeEventPolicy.isWaitingNotification(payload.notificationType)
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
            let questions = questionModels(from: payload.toolInput?["questions"])
            guard !questions.isEmpty else {
                return AgentPendingReply(
                    replyId: replyId,
                    kind: .question,
                    prompt: "Answer in Claude",
                    detail: "Agent Notch cannot represent this question faithfully."
                )
            }
            return AgentPendingReply(
                replyId: replyId,
                kind: .question,
                prompt: questions.count == 1
                    ? questions[0].text
                    : "Answer \(questions.count) questions",
                detail: nil,
                options: questions.count == 1 ? questions[0].options : [],
                questions: questions,
                grants: [.deny]
            )
        case "exitplanmode":
            let plan = payload.toolInput?["plan"]?.stringValue
                ?? payload.toolInput?["allowedPrompts"]?.stringValue
            return AgentPendingReply(
                replyId: replyId,
                kind: .plan,
                prompt: "Exit plan mode and start editing?",
                detail: plan,
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
        let command = originalText(payload.toolInput?["command"]?.stringValue)
        let file = payload.toolInput?["file_path"]?.stringValue
            ?? payload.toolInput?["filePath"]?.stringValue
            ?? payload.toolInput?["path"]?.stringValue
        let tool = payload.toolName.map(ProviderEventPolicy.displayTool)
        let detail = command
            ?? file
            ?? tool.map { "Allow \($0)?" }
        let prompt = command == nil
            ? ClaudeEventPolicy.approvalActivity(for: payload)
            : "Allow this command?"
        return AgentPendingReply(
            replyId: replyId,
            kind: .permission,
            prompt: prompt,
            detail: detail,
            grants: [.deny, .allow]
        )
    }

    private static func questionModels(from value: JSONValue?) -> [AgentPromptQuestion] {
        guard let values = value?.arrayValue, values.count <= 4 else { return [] }
        return values.compactMap { entry in
            guard let object = entry.objectValue,
                  let question = originalText(object["question"]?.stringValue)
            else { return nil }
            let options = options(from: object["options"])
            guard !options.isEmpty else { return nil }
            return AgentPromptQuestion(
                text: question,
                header: object["header"]?.stringValue?.nonEmpty,
                options: options,
                allowsMultiple: object["multiSelect"]?.boolValue ?? false
            )
        }
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
            grants: [.deny, .cancel]
        )
    }

    private static func options(from value: JSONValue?) -> [AgentPromptOption] {
        guard let values = value?.arrayValue else { return [] }
        return values.enumerated().compactMap { index, entry in
            if let label = originalText(entry.stringValue) {
                return AgentPromptOption(id: "option-\(index)", label: label)
            }
            let object = entry.objectValue
            let label = originalText(object?["label"]?.stringValue)
                ?? originalText(object?["title"]?.stringValue)
                ?? originalText(object?["text"]?.stringValue)
            guard let label else { return nil }
            // Keep a stable internal ID while the decision mapper returns labels.
            let id = "option-\(index)"
            return AgentPromptOption(id: id, label: label)
        }
    }

    /// Approval text and answer keys must retain the provider's exact value.
    private static func originalText(_ value: String?) -> String? {
        guard let value, value.nonEmpty != nil else { return nil }
        return value
    }
}
