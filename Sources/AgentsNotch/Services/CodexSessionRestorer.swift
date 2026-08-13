import AgentsNotchCore
import Foundation

enum CodexSessionRestorer {
    static func titleEvents(
        in sessions: [AgentSession],
        codexHome: URL
    ) -> [AgentEvent] {
        sessions.compactMap { session in
            guard session.provider == .codex,
                  session.parentSessionId == nil,
                  let threadID = CodexSessionTitleResolver.threadID(fromCanonicalSessionID: session.id),
                  let title = CodexSessionTitleResolver.title(
                    forNativeSessionId: threadID,
                    codexHome: codexHome
                  ),
                  title != session.task
            else { return nil }

            return AgentEvent(
                type: .activity,
                sessionId: session.id,
                provider: .codex,
                task: title,
                activity: session.currentActivity,
                state: session.state,
                timestamp: session.updatedAt,
                workingDirectory: session.workingDirectory,
                metadata: ["titleSource": "session"],
                parentSessionId: session.parentSessionId,
                agentRole: session.agentRole
            )
        }
    }
}
