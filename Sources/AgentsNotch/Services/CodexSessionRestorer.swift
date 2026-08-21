import AgentsNotchCore
import Foundation

/// Launch-time Codex title evidence from `session_index.jsonl`. Applies titles
/// to already-restored sessions and restamps missing index evidence; does not
/// invent live sessions from disk.
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
                  title != session.task || !session.hasOfficialSessionTitle
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
