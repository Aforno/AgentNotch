import Foundation

public struct AgentSession: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var provider: AgentProvider
    public var task: String
    public var currentActivity: String
    public var state: AgentState
    public var startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var workingDirectory: String?
    public var recentFiles: [String]
    public var recentEvents: [AgentEvent]
    public var applicationURL: URL?
    public var origin: AgentOrigin?
    public var parentSessionId: String?
    public var agentRole: String?
    public var plan: AgentPlan?
    public var workflows: [AgentWorkflow]

    public init(event: AgentEvent) {
        id = event.sessionId
        provider = event.provider
        task = event.task?.nonEmpty ?? "Untitled task"
        currentActivity = event.activity?.nonEmpty ?? event.resolvedState.displayName
        state = event.resolvedState
        startedAt = event.timestamp
        updatedAt = event.timestamp
        completedAt = state == .completed || state == .failed ? event.timestamp : nil
        workingDirectory = event.workingDirectory?.nonEmpty
        recentFiles = event.file?.nonEmpty.map { [$0] } ?? []
        recentEvents = [event]
        applicationURL = event.applicationURL
        origin = event.origin
        parentSessionId = event.parentSessionId
        agentRole = event.agentRole
        plan = event.plan
        workflows = []
        applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
        reconcilePlanWithTerminalState(at: event.timestamp)
    }

    public var isActive: Bool { state.isActive }
    public var needsAttention: Bool { state.needsAttention }
    public var isSubagent: Bool { parentSessionId != nil }

    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Bool {
        startedAt = min(startedAt, event.timestamp)
        let isTerminal = state == .completed || state == .failed
        let eventIsTerminal = event.resolvedState == .completed || event.resolvedState == .failed
        // A terminal session may begin another turn, but only an explicit lifecycle
        // event proves that. Delayed tool, workflow, notification, or file events
        // are history and must never resurrect a completed row.
        let terminalTransitionIsAllowed = !isTerminal || eventIsTerminal || event.explicitlyResumesSession
        // Symmetric reorder case: concurrent ingest can apply a later-timestamp
        // activity/tool event before an earlier completed/failed. Terminal still
        // wins over any active non-terminal so the session cannot stick running
        // (or waiting) forever while the terminal only appears in history.
        let isReorderedTerminalVsActive = !isTerminal && eventIsTerminal
        let sameTimeKeepsAttention = event.timestamp == updatedAt
            && state == .waitingForUser
            && !eventIsTerminal
            && !event.explicitlyResumesSession
        let advancesCurrentState = (event.timestamp >= updatedAt || isReorderedTerminalVsActive)
            && terminalTransitionIsAllowed
            && !sameTimeKeepsAttention
        if advancesCurrentState {
            provider = event.provider
            if let task = event.task?.nonEmpty { self.task = task }
            if let activity = event.activity?.nonEmpty { currentActivity = activity }
            state = event.resolvedState
            // Keep session clocks monotonic when an older terminal overrides active.
            updatedAt = max(updatedAt, event.timestamp)
            // Treat empty/whitespace cwd as absent so hook defaults of "" cannot
            // wipe a previously stored absolute path.
            if let directory = event.workingDirectory?.nonEmpty {
                workingDirectory = directory
            }
            applicationURL = event.applicationURL ?? applicationURL
            if let eventOrigin = event.origin, !eventOrigin.isEmpty {
                origin = eventOrigin
            }
            parentSessionId = event.parentSessionId ?? parentSessionId
            agentRole = event.agentRole ?? agentRole

            if state == .completed || state == .failed {
                completedAt = event.timestamp
            } else {
                completedAt = nil
            }

            // Only promote files from events that advance session time so
            // reordered stale file events cannot reshuffle recency.
            if let file = event.file?.nonEmpty {
                recentFiles.removeAll { $0 == file }
                recentFiles.insert(file, at: 0)
                recentFiles = Array(recentFiles.prefix(6))
            }

            // Plan/workflow follow the same session-time gate as state/files so a
            // reordered stale update_goal or plan snapshot cannot rewrite execution
            // UI while live state stays on a newer event.
            if let eventPlan = event.plan {
                if let currentPlan = plan {
                    if eventPlan.updatedAt >= currentPlan.updatedAt {
                        plan = eventPlan
                    }
                } else {
                    plan = eventPlan
                }
            }
            applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
            reconcilePlanWithTerminalState(at: event.timestamp)
        } else {
            // Non-advancing events (including equal-timestamp waiters blocked by
            // sameTimeKeepsAttention) may still carry hierarchy/origin from
            // reconciliation. Merge those without changing state or recency.
            if let eventOrigin = event.origin, !eventOrigin.isEmpty {
                origin = eventOrigin
            }
            parentSessionId = event.parentSessionId ?? parentSessionId
            agentRole = event.agentRole ?? agentRole
            if let directory = event.workingDirectory?.nonEmpty {
                workingDirectory = workingDirectory ?? directory
            }
            applicationURL = applicationURL ?? event.applicationURL
            // Plan/workflow only at equal-or-newer timestamps so a reordered
            // stale snapshot cannot rewrite execution UI under a newer state.
            if event.timestamp >= updatedAt {
                if let eventPlan = event.plan {
                    if let currentPlan = plan {
                        if eventPlan.updatedAt >= currentPlan.updatedAt {
                            plan = eventPlan
                        }
                    } else {
                        plan = eventPlan
                    }
                }
                applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
            }
            if task == "Untitled task", let task = event.task?.nonEmpty {
                self.task = task
            }
        }

        recentEvents.append(event)
        recentEvents.sort { $0.timestamp > $1.timestamp }
        recentEvents = Array(recentEvents.prefix(10))
        return advancesCurrentState
    }

    public mutating func complete(as terminalState: AgentState, at timestamp: Date) {
        guard terminalState == .completed || terminalState == .failed, isActive else { return }
        state = terminalState
        completedAt = timestamp
        updatedAt = max(updatedAt, timestamp)
        currentActivity = terminalState == .failed ? "Session failed" : "Session ended"
        reconcilePlanWithTerminalState(at: timestamp)
    }

    /// Marks an active session as cold-start-unverified without inventing a
    /// completion. Recency and last activity text are preserved so a mid-task
    /// restart does not look like the work finished.
    public mutating func markUnknown() {
        guard isActive, state != .waitingForUser, state != .unknown else { return }
        state = .unknown
        completedAt = nil
    }

    /// Applies lifecycle evidence discovered outside the live hook stream
    /// (for example Grok on-disk workflow status) without treating restore as
    /// a new agent turn.
    @discardableResult
    public mutating func applyRestoredLifecycle(
        state restoredState: AgentState,
        activity restoredActivity: String?,
        at timestamp: Date
    ) -> Bool {
        guard state == .unknown else { return false }
        if restoredState == .completed || restoredState == .failed {
            complete(as: restoredState, at: timestamp)
            return true
        }
        guard restoredState.isActive, restoredState != .unknown else { return false }
        state = restoredState
        if let restoredActivity = restoredActivity?.nonEmpty {
            currentActivity = restoredActivity
        }
        completedAt = nil
        return true
    }

    /// Merges a workflow snapshot discovered from Grok's on-disk session data.
    /// Restoration is not live agent activity, so it must not advance session
    /// recency or add a duplicate event on every app launch.
    @discardableResult
    public mutating func reconcileRestoredWorkflow(_ event: AgentEvent) -> Bool {
        guard provider == .grok, let update = event.workflowUpdate else { return false }
        var changed = repairLegacyRestoredWorkflowRecency(
            workflowID: update.id,
            authoritativeTimestamp: event.timestamp
        )

        if task == "Untitled task", let restoredTask = event.task?.nonEmpty {
            task = restoredTask
            changed = true
        }

        if let index = workflows.firstIndex(where: { $0.id == update.id }) {
            let title = update.title?.nonEmpty ?? workflows[index].title
            let status = update.status ?? workflows[index].status
            let steps = update.steps ?? workflows[index].steps
            if workflows[index].title != title
                || workflows[index].status != status
                || workflows[index].steps != steps
                || workflows[index].updatedAt != event.timestamp
            {
                workflows[index].title = title
                workflows[index].status = status
                workflows[index].steps = steps
                workflows[index].updatedAt = event.timestamp
                changed = true
            }
        } else {
            workflows.append(AgentWorkflow(
                id: update.id,
                title: update.title?.nonEmpty ?? "Workflow",
                status: update.status ?? .running,
                steps: update.steps ?? [],
                updatedAt: event.timestamp
            ))
            changed = true
        }
        workflows.sort { $0.updatedAt > $1.updatedAt }
        workflows = Array(workflows.prefix(6))
        return changed
    }

    private mutating func repairLegacyRestoredWorkflowRecency(
        workflowID: String,
        authoritativeTimestamp: Date
    ) -> Bool {
        // Older builds stamped startup reconciliation with Date(). Only repair
        // when the session's current recency is itself one of those later
        // synthetic workflow events. The tolerance preserves legitimate hook
        // delivery a few moments after state.json was written.
        let cutoff = authoritativeTimestamp.addingTimeInterval(5)
        let latestWasSyntheticRestore = recentEvents.contains { event in
            event.timestamp == updatedAt
                && event.timestamp > cutoff
                && event.isGrokWorkflowState
        }
        guard latestWasSyntheticRestore else { return false }

        recentEvents.removeAll { event in
            event.timestamp > cutoff && event.isGrokWorkflowState
        }

        let latestRemainingEvent = recentEvents.map(\.timestamp).max() ?? .distantPast
        let repairedUpdatedAt = max(max(startedAt, authoritativeTimestamp), latestRemainingEvent)
        updatedAt = repairedUpdatedAt

        if state == .completed || state == .failed {
            let latestTerminalEvent = recentEvents
                .filter { $0.resolvedState == .completed || $0.resolvedState == .failed }
                .map(\.timestamp)
                .max() ?? .distantPast
            completedAt = max(max(startedAt, authoritativeTimestamp), latestTerminalEvent)
        }

        if let index = workflows.firstIndex(where: { $0.id == workflowID }),
           workflows[index].updatedAt > cutoff
        {
            workflows[index].updatedAt = authoritativeTimestamp
        }
        return true
    }

    private mutating func applyWorkflowUpdate(_ update: AgentWorkflowUpdate?, at timestamp: Date) {
        guard let update else { return }
        if let index = workflows.firstIndex(where: { $0.id == update.id }) {
            guard timestamp >= workflows[index].updatedAt else { return }
            workflows[index].title = update.title?.nonEmpty ?? workflows[index].title
            workflows[index].status = update.status ?? workflows[index].status
            workflows[index].steps = update.steps ?? workflows[index].steps
            workflows[index].updatedAt = timestamp
        } else {
            workflows.append(AgentWorkflow(
                id: update.id,
                title: update.title?.nonEmpty ?? "Workflow",
                status: update.status ?? .running,
                steps: update.steps ?? [],
                updatedAt: timestamp
            ))
        }
        workflows.sort { $0.updatedAt > $1.updatedAt }
        workflows = Array(workflows.prefix(6))
    }

    private mutating func reconcilePlanWithTerminalState(at timestamp: Date) {
        guard state == .completed else { return }
        plan?.completeUnfinishedSteps(at: timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case id, provider, task, currentActivity, state, startedAt, updatedAt, completedAt
        case workingDirectory, recentFiles, recentEvents, applicationURL, origin
        case parentSessionId, agentRole, plan, workflows
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        provider = try values.decode(AgentProvider.self, forKey: .provider)
        task = try values.decode(String.self, forKey: .task)
        currentActivity = try values.decode(String.self, forKey: .currentActivity)
        state = try values.decode(AgentState.self, forKey: .state)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        workingDirectory = try values.decodeIfPresent(String.self, forKey: .workingDirectory)
        recentFiles = Array(try values.decode([String].self, forKey: .recentFiles).prefix(6))
        recentEvents = Array(
            try values.decode([AgentEvent].self, forKey: .recentEvents)
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(10)
        )
        applicationURL = try values.decodeIfPresent(URL.self, forKey: .applicationURL)
        origin = try values.decodeIfPresent(AgentOrigin.self, forKey: .origin)
        parentSessionId = try values.decodeIfPresent(String.self, forKey: .parentSessionId)
        agentRole = try values.decodeIfPresent(String.self, forKey: .agentRole)
        plan = try values.decodeIfPresent(AgentPlan.self, forKey: .plan)
        workflows = Array(
            (try values.decodeIfPresent([AgentWorkflow].self, forKey: .workflows) ?? [])
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(6)
        )
        reconcilePlanWithTerminalState(at: completedAt ?? updatedAt)
    }
}

private extension AgentEvent {
    var isGrokWorkflowState: Bool {
        metadata?["hookEvent"] == "grokWorkflowState"
    }

    var explicitlyResumesSession: Bool {
        if type == .started { return true }
        guard let hookEvent = metadata?["hookEvent"] else { return false }
        switch hookEvent
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        {
        // Claude/Codex/Grok prompt events and Gemini's BeforeAgent alias.
        case "userpromptsubmit", "beforeagent":
            return true
        default:
            return false
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
