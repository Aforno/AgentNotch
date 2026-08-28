import Foundation

public enum AgentHookEventMapper {
    public static func map(
        _ payload: AgentHookPayload,
        provider: AgentProvider,
        permissionRequestRequiresUserInput: Bool = true,
        now: Date = Date()
    ) -> AgentEvent? {
        let context = mappingContext(for: payload, provider: provider, now: now)
        guard var event = mappedEvent(
            payload,
            permissionRequestRequiresUserInput: permissionRequestRequiresUserInput,
            context: context
        ) else { return nil }

        let eventTimestamp = payload.timestamp ?? now
        event.timestamp = eventTimestamp
        event.plan?.updatedAt = eventTimestamp
        event.parentSessionId = context.parentSessionId
        event.agentRole = payload.description?.nonEmpty ?? payload.agentType
        return event
    }

    private struct MappingContext {
        let provider: AgentProvider
        let sessionId: String
        let parentSessionId: String?
        let now: Date
        let workingDirectory: String?
        let metadata: [String: String]

        func event(
            type: AgentEventType,
            task: String? = nil,
            activity: String,
            state: AgentState
        ) -> AgentEvent {
            AgentEvent(
                type: type,
                sessionId: sessionId,
                provider: provider,
                task: task,
                activity: activity,
                state: state,
                timestamp: now,
                workingDirectory: workingDirectory,
                metadata: metadata
            )
        }
    }

    private static func mappingContext(
        for payload: AgentHookPayload,
        provider: AgentProvider,
        now: Date
    ) -> MappingContext {
        let nativeSessionId: String
        if let agentId = payload.agentId, !agentId.isEmpty {
            nativeSessionId = "\(payload.sessionId):\(agentId)"
        } else {
            nativeSessionId = payload.sessionId
        }
        let nativeParentSessionId = payload.parentSessionId?.nonEmpty
            ?? (payload.agentId?.isEmpty == false ? payload.sessionId : nil)

        let metadata = [
            "model": payload.model,
            "turnId": payload.turnId,
            // Store the canonical lifecycle name when the provider uses an
            // alias (e.g. Gemini BeforeAgent → UserPromptSubmit) so session
            // resume and other hookEvent gates stay provider-neutral.
            "hookEvent": HookEventName.metadataName(for: payload.hookEventName),
        ].compactMapValues { $0 }

        return MappingContext(
            provider: provider,
            sessionId: provider.namespacedSessionID(nativeSessionId),
            parentSessionId: nativeParentSessionId.map { provider.namespacedSessionID($0) },
            now: now,
            workingDirectory: payload.cwd.nonEmpty,
            metadata: metadata
        )
    }

    private static func mappedEvent(
        _ payload: AgentHookPayload,
        permissionRequestRequiresUserInput: Bool,
        context: MappingContext
    ) -> AgentEvent? {
        switch HookEventName(rawEventName: payload.hookEventName) {
        case .sessionStart:
            return sessionStartEvent(payload, context: context)

        case .userPromptSubmit:
            return context.event(
                type: .activity,
                task: payload.prompt.flatMap { prompt in
                    AgentTaskTitle.fromPrompt(visiblePrompt(prompt, provider: context.provider))
                },
                activity: "Thinking",
                state: .thinking
            )

        case .preToolUse:
            if ProviderEventPolicy.isInteractiveTool(payload.toolName) {
                return context.event(
                    type: .waiting,
                    activity: ProviderEventPolicy.interactiveToolActivity(for: payload),
                    state: .waitingForUser
                )
            }
            return toolEvent(payload, completed: false, context: context)

        case .postToolUse:
            return toolEvent(payload, completed: true, context: context)

        case .postToolUseFailure:
            return context.event(
                type: .toolCompleted,
                activity: payload.error.map {
                    "Tool failed: \(ProviderEventPolicy.concise($0, limit: 76))"
                } ?? "Tool failed",
                state: .running
            )

        case .permissionRequest where permissionRequestRequiresUserInput:
            return context.event(
                type: .waiting,
                activity: ProviderEventPolicy.approvalActivity(for: payload),
                state: .waitingForUser
            )

        case .permissionRequest:
            return nil

        case .permissionDenied:
            return context.event(
                type: .activity,
                activity: payload.reason.map { ProviderEventPolicy.concise($0, limit: 90) }
                    ?? "Tool permission denied",
                state: .running
            )

        case .elicitation:
            return context.event(
                type: .waiting,
                activity: ProviderEventPolicy.waitingNotificationActivity(
                    for: "elicitation_dialog",
                    message: payload.notificationMessage
                ),
                state: .waitingForUser
            )

        case .elicitationResult:
            return context.event(
                type: .activity,
                activity: "Input received",
                state: .running
            )

        case .notification where ProviderEventPolicy.isWaitingNotification(payload.notificationType):
            return context.event(
                type: .waiting,
                activity: ProviderEventPolicy.waitingNotificationActivity(
                    for: payload.notificationType,
                    message: payload.notificationMessage
                ),
                state: .waitingForUser
            )

        case .stop:
            return terminalEvent(
                payload,
                successActivity: completionActivity(from: payload.lastAssistantMessage),
                failureActivity: "Task failed",
                context: context
            )

        case .stopFailure:
            return context.event(
                type: .failed,
                activity: payload.error.map { ProviderEventPolicy.concise($0, limit: 90) }
                    ?? "Turn failed",
                state: .failed
            )

        case .sessionEnd:
            return terminalEvent(
                payload,
                successActivity: "Session ended",
                failureActivity: "Session failed",
                context: context
            )

        case .subagentStart:
            return subagentEvent(payload, started: true, context: context)

        case .subagentStop:
            return subagentEvent(payload, started: false, context: context)

        case .notification, nil:
            return nil
        }
    }

    private static func sessionStartEvent(
        _ payload: AgentHookPayload,
        context: MappingContext
    ) -> AgentEvent? {
        guard ProviderEventPolicy.shouldMapSessionStart(
            provider: context.provider,
            source: payload.source
        ) else { return nil }
        return context.event(
            type: .started,
            task: repositoryName(from: context.workingDirectory, provider: context.provider),
            activity: "Session started",
            state: .starting
        )
    }

    private static func terminalEvent(
        _ payload: AgentHookPayload,
        successActivity: String,
        failureActivity: String,
        context: MappingContext
    ) -> AgentEvent {
        if isFailureReason(payload.reason) {
            return context.event(
                type: .failed,
                activity: payload.error.map { ProviderEventPolicy.concise($0, limit: 90) }
                    ?? failureActivity,
                state: .failed
            )
        }
        return context.event(
            type: .completed,
            activity: successActivity,
            state: .completed
        )
    }

    private static func subagentEvent(
        _ payload: AgentHookPayload,
        started: Bool,
        context: MappingContext
    ) -> AgentEvent {
        if ProviderEventPolicy.remapsParentScopedSubagent(
            provider: context.provider,
            payload: payload,
            parentSessionId: context.parentSessionId
        ) {
            // Grok fires these hooks in the parent and puts the parent's ID in
            // sessionId. Keep the parent active without creating a fake child.
            return context.event(
                type: .activity,
                activity: started ? "Running subagents" : "Subagent completed",
                state: .running
            )
        }
        if started {
            let role = payload.description?.nonEmpty
                ?? payload.agentType?.nonEmpty.map { $0.capitalized }
            return context.event(
                type: .started,
                task: role.map { "\($0) subagent" } ?? "\(context.provider.displayName) subagent",
                activity: "Subagent started",
                state: .starting
            )
        }
        return context.event(
            type: .completed,
            activity: "Subagent completed",
            state: .completed
        )
    }

    private static func toolEvent(
        _ payload: AgentHookPayload,
        completed: Bool,
        context: MappingContext
    ) -> AgentEvent {
        let presentation = ProviderEventPolicy.toolPresentation(
            payload: payload,
            completed: completed,
            sessionId: context.sessionId,
            now: context.now
        )
        return AgentEvent(
            type: presentation.type,
            sessionId: context.sessionId,
            provider: context.provider,
            activity: presentation.activity,
            state: presentation.state,
            timestamp: context.now,
            workingDirectory: context.workingDirectory,
            file: presentation.file,
            metadata: context.metadata.merging(
                ["tool": presentation.rawTool],
                uniquingKeysWith: { _, new in new }
            ),
            plan: presentation.plan,
            workflowUpdate: presentation.workflowUpdate
        )
    }

    private static func isFailureReason(_ reason: String?) -> Bool {
        switch reason?.replacingOccurrences(of: "-", with: "_").lowercased() {
        case "error", "failed", "failure", "aborted", "abort": true
        default: false
        }
    }

    private static func completionActivity(from message: String?) -> String {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Task completed"
        }
        return ProviderEventPolicy.concise(message, limit: 90)
    }

    private static func repositoryName(from cwd: String?, provider: AgentProvider) -> String {
        cwd.flatMap(ProjectIdentity.name(fromWorkingDirectory:))
            ?? "\(provider.displayName) session"
    }

    private static func visiblePrompt(_ prompt: String, provider: AgentProvider) -> String {
        switch provider {
        case .grok:
            return GrokEventPolicy.visiblePrompt(prompt)
        default:
            return prompt
        }
    }
}
