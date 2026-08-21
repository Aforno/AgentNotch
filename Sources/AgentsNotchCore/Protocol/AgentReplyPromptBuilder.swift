import Foundation

/// Builds a notch prompt from a provider hook payload. The hook process adds
/// `replyId` before it waits for an answer.
public enum AgentReplyPromptBuilder {
    public static func make(
        payload: AgentHookPayload,
        replyId: UUID
    ) -> AgentPendingReply? {
        if ProviderEventPolicy.isInteractiveTool(payload.toolName) {
            return interactivePrompt(payload: payload, replyId: replyId)
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
                    ? ProviderEventPolicy.concise(questions[0].text, limit: 160)
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
            grants: [.deny, .allow]
        )
    }

    private static func questionModels(from value: JSONValue?) -> [AgentPromptQuestion] {
        guard let values = value?.arrayValue, values.count <= 4 else { return [] }
        return values.compactMap { entry in
            guard let object = entry.objectValue,
                  let question = object["question"]?.stringValue?.nonEmpty
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
            if let label = entry.stringValue?.nonEmpty {
                return AgentPromptOption(id: "option-\(index)", label: label)
            }
            let object = entry.objectValue
            let label = object?["label"]?.stringValue?.nonEmpty
                ?? object?["title"]?.stringValue?.nonEmpty
                ?? object?["text"]?.stringValue?.nonEmpty
            guard let label else { return nil }
            // Keep a stable internal ID while the decision mapper returns labels.
            let id = "option-\(index)"
            return AgentPromptOption(id: id, label: ProviderEventPolicy.concise(label, limit: 48))
        }
    }
}
