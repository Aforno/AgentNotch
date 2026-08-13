import AgentsNotchCore
import Foundation

struct GrokRestoreEvidence: Sendable {
    let relationshipEvents: [AgentEvent]
    let workflowEvents: [AgentEvent]
}

/// Reads provider-owned Grok state without turning startup restoration into
/// live activity. Applying the evidence remains AppRuntime's responsibility.
enum GrokSessionRestorer {
    static func discover(
        in sessions: [AgentSession],
        grokHome: URL
    ) -> GrokRestoreEvidence {
        let grokPrefix = "\(AgentProvider.grok.rawValue):"
        var workflowContexts: [String: GrokSessionContext] = [:]
        var relationshipEvents: [AgentEvent] = []

        for session in sessions where session.provider == .grok {
            guard session.id.hasPrefix(grokPrefix),
                  let workspace = session.workingDirectory
            else { continue }

            let nativeSessionID = String(session.id.dropFirst(grokPrefix.count))
            let context = GrokSessionContextResolver.resolve(
                sessionId: nativeSessionID,
                workspaceRoot: workspace,
                grokHome: grokHome
            )
            if let parent = context.parentSessionId {
                relationshipEvents.append(
                    relationshipEvent(
                        for: session,
                        parentSessionID: grokPrefix + parent,
                        agentRole: context.agentRole
                    )
                )
            }
            if AgentTaskTitle.displayable(session.task) == nil,
               let sessionTitle = context.sessionTitle
            {
                relationshipEvents.append(
                    titleEvent(for: session, title: sessionTitle)
                )
            }
            if let owner = context.workflowOwnerSessionId {
                workflowContexts[owner] = context
            }
        }

        let workflowEvents = workflowContexts.values
            .compactMap { context -> AgentEvent? in
                guard let workflowUpdatedAt = context.workflowUpdatedAt else { return nil }
                return context.workflowEvent(now: workflowUpdatedAt, workingDirectory: nil)
            }
            .sorted { $0.sessionId < $1.sessionId }

        return GrokRestoreEvidence(
            relationshipEvents: relationshipEvents,
            workflowEvents: workflowEvents
        )
    }

    private static func relationshipEvent(
        for session: AgentSession,
        parentSessionID: String,
        agentRole: String?
    ) -> AgentEvent {
        AgentEvent(
            type: .activity,
            sessionId: session.id,
            provider: .grok,
            activity: session.currentActivity,
            state: session.state,
            timestamp: session.updatedAt,
            workingDirectory: session.workingDirectory,
            parentSessionId: parentSessionID,
            agentRole: agentRole
        )
    }

    private static func titleEvent(for session: AgentSession, title: String) -> AgentEvent {
        AgentEvent(
            type: .activity,
            sessionId: session.id,
            provider: .grok,
            task: title,
            activity: session.currentActivity,
            state: session.state,
            timestamp: session.updatedAt,
            workingDirectory: session.workingDirectory,
            parentSessionId: session.parentSessionId,
            agentRole: session.agentRole
        )
    }
}
