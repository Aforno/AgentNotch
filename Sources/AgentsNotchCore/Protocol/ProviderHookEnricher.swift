import Foundation

/// Disk-backed hook enrichment used only by the short-lived hook process.
/// Does not invent live sessions.
public struct ProviderHookEnrichment: Sendable {
    public var payload: AgentHookPayload
    public var permissionRequestRequiresUserInput: Bool
    public var preferredTask: String?
    public var titleSource: String?
    public var replaceExistingTask: Bool
    public var workflowEvent: AgentEvent?
}

public enum ProviderHookEnricher {
    public static func enrich(
        _ payload: AgentHookPayload,
        provider: AgentProvider,
        now: Date = Date()
    ) -> ProviderHookEnrichment {
        switch provider {
        case .grok:
            return Grok.enrich(payload, now: now)
        case .codex:
            return Codex.enrich(payload)
        default:
            return ProviderHookEnrichment(
                payload: payload,
                permissionRequestRequiresUserInput: true,
                preferredTask: nil,
                titleSource: nil,
                replaceExistingTask: false,
                workflowEvent: nil
            )
        }
    }

    public enum Grok {
        public static func enrich(
            _ payload: AgentHookPayload,
            now: Date
        ) -> ProviderHookEnrichment {
            var payload = payload
            let context: GrokSessionContext?
            if GrokEventPolicy.shouldResolveSessionContext(payload) {
                context = GrokSessionContextResolver.resolve(payload)
            } else {
                context = nil
            }
            if let context {
                payload.parentSessionId = context.parentSessionId ?? payload.parentSessionId
                payload.description = context.agentRole ?? payload.description
            }

            var workflowEvent = context.flatMap {
                guard GrokEventPolicy.shouldPublishWorkflowState(payload) else {
                    return nil as AgentEvent?
                }
                return $0.workflowEvent(
                    now: now,
                    workingDirectory: payload.workspaceRoot ?? payload.cwd
                )
            }
            if var event = workflowEvent,
               HookEventName(rawEventName: payload.hookEventName)?.isTerminal == true,
               event.resolvedState.isActive
            {
                // Stop/SessionEnd already sent a completed event. On-disk workflow
                // status is often still active; do not reopen the session.
                event.type = .completed
                event.state = .completed
                workflowEvent = event
            }

            return ProviderHookEnrichment(
                payload: payload,
                permissionRequestRequiresUserInput: true,
                preferredTask: context?.sessionTitle,
                titleSource: nil,
                replaceExistingTask: false,
                workflowEvent: workflowEvent
            )
        }
    }

    public enum Codex {
        public static func enrich(_ payload: AgentHookPayload) -> ProviderHookEnrichment {
            var preferredTask: String?
            var titleSource: String?
            if payload.agentId?.nonEmpty == nil,
               payload.parentSessionId?.nonEmpty == nil,
               let title = CodexSessionTitleResolver.title(forNativeSessionId: payload.sessionId)
            {
                preferredTask = title
                titleSource = "session"
            }
            return ProviderHookEnrichment(
                payload: payload,
                permissionRequestRequiresUserInput:
                    CodexApprovalContextResolver.permissionRequestRequiresUserInput(for: payload),
                preferredTask: preferredTask,
                titleSource: titleSource,
                replaceExistingTask: preferredTask != nil,
                workflowEvent: nil
            )
        }
    }
}
