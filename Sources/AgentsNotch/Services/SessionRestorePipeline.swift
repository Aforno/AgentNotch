import AgentsNotchCore
import Foundation

/// Launch-time restore: load history, reconcile runners, apply provider-owned
/// title/hierarchy evidence, then persist the normalized snapshot.
@MainActor
enum SessionRestorePipeline {
    struct Result {
        let writesAllowed: Bool
        let persistenceError: String?
        let persistenceRecoveryNotice: String?
    }

    static func restore(
        generation: Int,
        activity: AgentActivityService,
        persistence: SessionPersistence,
        grokHome: URL,
        codexHome: URL,
        persistableSessions: @MainActor () -> [AgentSession],
        historyRetentionDays: () -> Int?,
        isCurrentLifecycle: (Int) -> Bool,
        resetSimulator: () -> Void
    ) async -> Result? {
        let loadResult = await persistence.load()
        guard isCurrentLifecycle(generation) else { return nil }
        var persistenceError: String?
        var persistenceRecoveryNotice: String?
        if loadResult.canSafelyWrite {
            persistenceRecoveryNotice = loadResult.recoveryMessage
        } else {
            persistenceError = loadResult.recoveryMessage
        }
        activity.replaceSessions(loadResult.sessions)
        activity.reconcileUnverifiedActiveSessions()
        let restoredSessions = activity.sessions
        let grokEvidence = await Task.detached(priority: .utility) {
            GrokSessionRestorer.discover(in: restoredSessions, grokHome: grokHome)
        }.value
        guard isCurrentLifecycle(generation) else { return nil }
        applyGrokSessionContext(grokEvidence, to: activity)
        let restoredAfterGrok = activity.sessions
        let codexTitleEvents = await Task.detached(priority: .utility) {
            CodexSessionRestorer.titleEvents(in: restoredAfterGrok, codexHome: codexHome)
        }.value
        guard isCurrentLifecycle(generation) else { return nil }
        for event in codexTitleEvents {
            activity.ingest(event)
        }
        pruneHistory(activity: activity, historyRetentionDays: historyRetentionDays)
        resetSimulator()
        if loadResult.canSafelyWrite {
            // Persist prefixed identities, restored Grok relationships, and a
            // clean file after successful corruption quarantine.
            if let error = await persistence.save(persistableSessions()) {
                persistenceError = error
            }
        }
        guard isCurrentLifecycle(generation) else { return nil }
        return Result(
            writesAllowed: loadResult.canSafelyWrite,
            persistenceError: persistenceError,
            persistenceRecoveryNotice: persistenceRecoveryNotice
        )
    }

    private static func applyGrokSessionContext(
        _ evidence: GrokRestoreEvidence,
        to activity: AgentActivityService
    ) {
        for event in evidence.relationshipEvents {
            activity.ingest(event)
        }

        for discoveredEvent in evidence.workflowEvents {
            var event = discoveredEvent
            if let session = activity.session(id: event.sessionId) {
                if session.state == .unknown {
                    // On-disk Grok workflow status is stronger evidence than
                    // cold-start uncertainty: complete finished runs and restore
                    // active ones instead of inventing a generic completion.
                    activity.applyRestoredLifecycle(
                        sessionId: session.id,
                        state: event.resolvedState,
                        activity: event.activity,
                        at: event.timestamp
                    )
                } else if !session.isActive, event.resolvedState.isActive {
                    // Leftover on-disk workflow status (e.g. active/running) must
                    // not reopen terminal sessions as phantoms across relaunch.
                    event.state = session.state
                    event.type = session.state == .failed ? .failed : .completed
                }
            }
            activity.reconcileRestoredWorkflow(event)
        }
    }

    private static func pruneHistory(
        activity: AgentActivityService,
        historyRetentionDays: () -> Int?
    ) {
        guard let age = SessionHistoryPolicy.completedSessionRetentionAge(
            configuredDays: historyRetentionDays()
        ) else { return }
        activity.pruneCompleted(olderThan: age)
    }
}
