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
    /// Display name for the working copy. Linked git worktrees keep the main
    /// repository name even after their on-disk metadata is removed.
    public private(set) var projectName: String?
    public var recentFiles: [String]
    public var recentEvents: [AgentEvent]
    public var applicationURL: URL?
    public var origin: AgentOrigin?
    public var parentSessionId: String?
    public var agentRole: String?
    public var plan: AgentPlan?
    public var workflows: [AgentWorkflow]
    public var pendingReply: AgentPendingReply?
    public var pendingReplies: [AgentPendingReply]
    /// Sticky Codex index evidence so Open in Codex does not depend on the event ring.
    public var hasOfficialSessionTitle: Bool
    /// Sticky helper classification so an official title or the event ring cannot un-hide it.
    public var isInternalHelper: Bool

    public init(event: AgentEvent) {
        id = event.sessionId
        provider = event.provider
        let initialProjectName = Self.projectName(from: event.workingDirectory)
        task = Self.resolvedTask(
            current: AgentTaskTitle.untitled,
            event: event,
            projectName: initialProjectName
        )
        currentActivity = event.activity?.nonEmpty ?? event.resolvedState.displayName
        state = event.resolvedState
        startedAt = event.timestamp
        updatedAt = event.timestamp
        completedAt = state == .completed || state == .failed ? event.timestamp : nil
        workingDirectory = event.workingDirectory?.nonEmpty
        projectName = initialProjectName
        recentFiles = event.file?.nonEmpty.map { [$0] } ?? []
        recentEvents = [event]
        applicationURL = event.applicationURL
        origin = event.origin
        parentSessionId = event.parentSessionId
        agentRole = event.agentRole
        plan = event.plan
        workflows = []
        pendingReply = event.resolvedState == .waitingForUser ? event.pendingReply : nil
        pendingReplies = pendingReply.map { [$0] } ?? []
        hasOfficialSessionTitle = event.hasOfficialSessionTitle
        isInternalHelper = AgentTaskTitle.isInternalHelper(task, provider: provider)
            || event.task.map { AgentTaskTitle.isInternalHelper($0, provider: event.provider) } == true
        applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
        reconcilePlanWithTerminalState(at: event.timestamp)
    }

    public var isActive: Bool { state.isActive }
    public var needsAttention: Bool { state.needsAttention }
    public var isSubagent: Bool { parentSessionId != nil }

    /// Ring-buffer size for per-session event history. The Activity Center
    /// timeline renders from this list, so it bounds how far back the timeline
    /// can reach. Keep the decode path capped at the same value.
    public static let recentEventLimit = 50

    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Bool {
        startedAt = min(startedAt, event.timestamp)
        let advancesCurrentState = AdvanceDecision(
            currentState: state,
            updatedAt: updatedAt,
            event: event
        ).advancesCurrentState

        if advancesCurrentState {
            applyAdvancingEvent(event)
        } else {
            mergeNonAdvancingEvent(event)
        }

        if event.hasOfficialSessionTitle {
            hasOfficialSessionTitle = true
        }
        if let incoming = event.task, AgentTaskTitle.isInternalHelper(incoming, provider: event.provider) {
            isInternalHelper = true
        }
        recordRecentEvent(event)
        return advancesCurrentState
    }

    /// Named session-time policy. The hold reasons are independently discovered
    /// bugs; keep them together and do not change behavior without the reducer
    /// tests that lock each case.
    private enum AdvanceDecision {
        case advance
        case hold(HoldReason)

        enum HoldReason {
            case staleTimestamp
            case terminalResurrection
            case sameTimeAttention
            case startRegression
        }

        init(currentState: AgentState, updatedAt: Date, event: AgentEvent) {
            let isTerminal = currentState == .completed || currentState == .failed
            let eventIsTerminal = event.resolvedState == .completed || event.resolvedState == .failed
            if Self.startRegression(currentState: currentState, event: event, eventIsTerminal: eventIsTerminal) {
                self = .hold(.startRegression)
                return
            }
            if Self.sameTimeAttention(currentState: currentState, updatedAt: updatedAt, event: event, eventIsTerminal: eventIsTerminal) {
                self = .hold(.sameTimeAttention)
                return
            }
            if Self.terminalResurrection(
                isTerminal: isTerminal,
                eventIsTerminal: eventIsTerminal,
                event: event
            ) {
                self = .hold(.terminalResurrection)
                return
            }
            if event.timestamp >= updatedAt || Self.reorderedTerminal(isTerminal: isTerminal, eventIsTerminal: eventIsTerminal) {
                self = .advance
                return
            }
            self = .hold(.staleTimestamp)
        }

        var advancesCurrentState: Bool {
            if case .advance = self { return true }
            return false
        }

        /// Delayed SessionStart is often stamped with Date() when the hook
        /// omits a timestamp. Do not rewind an already-progressed active
        /// session back to .starting or clear waiting attention.
        private static func startRegression(
            currentState: AgentState,
            event: AgentEvent,
            eventIsTerminal: Bool
        ) -> Bool {
            event.type == .started
                && !eventIsTerminal
                && (currentState == .thinking
                    || currentState == .running
                    || currentState == .executingTool
                    || currentState == .editing
                    || currentState == .waitingForUser)
        }

        private static func sameTimeAttention(
            currentState: AgentState,
            updatedAt: Date,
            event: AgentEvent,
            eventIsTerminal: Bool
        ) -> Bool {
            event.timestamp == updatedAt
                && currentState == .waitingForUser
                && !eventIsTerminal
                && !event.explicitlyResumesSession
        }

        /// A terminal session may begin another turn, but only an explicit
        /// lifecycle event proves that. Delayed tool, workflow, notification,
        /// or file events are history and must never resurrect a completed row.
        private static func terminalResurrection(
            isTerminal: Bool,
            eventIsTerminal: Bool,
            event: AgentEvent
        ) -> Bool {
            isTerminal && !eventIsTerminal && !event.explicitlyResumesSession
        }

        /// Concurrent ingest can apply a later-timestamp activity/tool event
        /// before an earlier completed/failed. Terminal still wins.
        private static func reorderedTerminal(isTerminal: Bool, eventIsTerminal: Bool) -> Bool {
            !isTerminal && eventIsTerminal
        }
    }

    private mutating func applyAdvancingEvent(_ event: AgentEvent) {
        provider = event.provider
        let eventProjectName = resolvedProjectName(for: event.workingDirectory)
        applyTask(from: event, projectName: eventProjectName)
        if let activity = event.activity?.nonEmpty { currentActivity = activity }
        state = event.resolvedState
        // Keep session clocks monotonic when an older terminal overrides active.
        updatedAt = max(updatedAt, event.timestamp)
        // Treat empty/whitespace cwd as absent so hook defaults of "" cannot
        // wipe a previously stored absolute path.
        if let directory = event.workingDirectory?.nonEmpty {
            workingDirectory = directory
            projectName = eventProjectName
        }
        applicationURL = event.applicationURL ?? applicationURL
        mergeRelationshipContext(from: event)
        completedAt = state == .completed || state == .failed ? event.timestamp : nil

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
        mergePlan(from: event)
        applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
        reconcilePlanWithTerminalState(at: event.timestamp)
        applyPendingReply(from: event)
    }

    private mutating func mergeNonAdvancingEvent(_ event: AgentEvent) {
        // Non-advancing events may still carry relationship context discovered
        // during reconciliation. Merge it without changing state or recency.
        mergeRelationshipContext(from: event)
        let eventProjectName = resolvedProjectName(for: event.workingDirectory)
        if let directory = event.workingDirectory?.nonEmpty {
            if workingDirectory == nil {
                workingDirectory = directory
                projectName = eventProjectName
            }
        }
        applicationURL = applicationURL ?? event.applicationURL
        // Plan/workflow only at equal-or-newer timestamps so a reordered stale
        // snapshot cannot rewrite execution UI under a newer state.
        if event.timestamp >= updatedAt {
            mergePlan(from: event)
            applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
        }
        applyTask(from: event, projectName: eventProjectName)
        if event.resolvedState == .waitingForUser, let pending = event.pendingReply {
            mergePendingReply(pending)
        }
    }

    private mutating func applyPendingReply(from event: AgentEvent) {
        if event.resolvedState == .waitingForUser {
            if let pending = event.pendingReply {
                mergePendingReply(pending)
            }
        } else if event.resolvedState == .completed || event.resolvedState == .failed {
            pendingReplies.removeAll()
            pendingReply = nil
        }
    }

    private mutating func mergePendingReply(_ pending: AgentPendingReply) {
        pendingReplies.removeAll { $0.replyId == pending.replyId }
        pendingReplies.append(pending)
        pendingReply = pending
    }

    public mutating func retainPendingReplies(where isLive: (UUID) -> Bool) {
        pendingReplies.removeAll { !isLive($0.replyId) }
        pendingReply = pendingReplies.last
    }

    private mutating func applyTask(from event: AgentEvent, projectName: String?) {
        task = Self.resolvedTask(
            current: task,
            event: event,
            projectName: projectName
        )
    }

    private static func resolvedTask(
        current: String,
        event: AgentEvent,
        projectName: String?
    ) -> String {
        if event.hasOfficialSessionTitle,
           let official = event.task.flatMap(AgentTaskTitle.displayable)
        {
            return official
        }
        return AgentTaskTitle.assigned(
            current: current,
            incoming: event.task,
            projectName: projectName
        )
    }

    private static func projectName(from directory: String?) -> String? {
        directory.flatMap(ProjectIdentity.name(fromWorkingDirectory:))
    }

    /// Reuse the stored name while an event remains in the same working copy.
    /// Worktree metadata is often deleted before its completed session expires.
    private func resolvedProjectName(for eventDirectory: String?) -> String? {
        guard let directory = eventDirectory?.nonEmpty ?? workingDirectory else {
            return projectName
        }
        if directory == workingDirectory, let projectName {
            return projectName
        }
        return Self.projectName(from: directory)
    }

    private mutating func mergeRelationshipContext(from event: AgentEvent) {
        if let eventOrigin = event.origin, !eventOrigin.isEmpty {
            origin = eventOrigin
        }
        parentSessionId = event.parentSessionId ?? parentSessionId
        agentRole = event.agentRole ?? agentRole
    }

    private mutating func mergePlan(from event: AgentEvent) {
        guard let eventPlan = event.plan else { return }
        guard let currentPlan = plan else {
            plan = eventPlan
            return
        }
        if eventPlan.updatedAt >= currentPlan.updatedAt {
            plan = eventPlan
        }
    }

    private mutating func recordRecentEvent(_ event: AgentEvent) {
        recentEvents.append(event)
        recentEvents.sort { $0.timestamp > $1.timestamp }
        recentEvents = Array(recentEvents.prefix(Self.recentEventLimit))
    }

    public mutating func complete(as terminalState: AgentState, at timestamp: Date) {
        guard terminalState == .completed || terminalState == .failed, isActive else { return }
        state = terminalState
        completedAt = timestamp
        updatedAt = max(updatedAt, timestamp)
        currentActivity = terminalState == .failed ? "Session failed" : "Session ended"
        pendingReply = nil
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

        if AgentTaskTitle.displayable(task) == nil, let restoredTask = event.task.flatMap(AgentTaskTitle.displayable) {
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
        case workingDirectory, projectName, recentFiles, recentEvents, applicationURL, origin
        case parentSessionId, agentRole, plan, workflows, pendingReply, pendingReplies
        case hasOfficialSessionTitle, isInternalHelper
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        provider = try values.decode(AgentProvider.self, forKey: .provider)
        let decodedTask = try values.decode(String.self, forKey: .task)
        task = AgentTaskTitle.isHousekeeping(decodedTask)
            ? decodedTask
            : (AgentTaskTitle.displayable(decodedTask) ?? AgentTaskTitle.untitled)
        currentActivity = try values.decode(String.self, forKey: .currentActivity)
        state = try values.decode(AgentState.self, forKey: .state)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        workingDirectory = try values.decodeIfPresent(String.self, forKey: .workingDirectory)
        projectName = try values.decodeIfPresent(String.self, forKey: .projectName)?.nonEmpty
            ?? Self.projectName(from: workingDirectory)
        recentFiles = Array(try values.decode([String].self, forKey: .recentFiles).prefix(6))
        recentEvents = Array(
            try values.decode([AgentEvent].self, forKey: .recentEvents)
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(Self.recentEventLimit)
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
        pendingReply = try values.decodeIfPresent(AgentPendingReply.self, forKey: .pendingReply)
        pendingReplies = try values.decodeIfPresent([AgentPendingReply].self, forKey: .pendingReplies)
            ?? pendingReply.map { [$0] }
            ?? []
        if state != .waitingForUser {
            pendingReply = nil
            pendingReplies.removeAll()
        }
        hasOfficialSessionTitle = try values.decodeIfPresent(Bool.self, forKey: .hasOfficialSessionTitle)
            ?? recentEvents.contains { $0.hasOfficialSessionTitle }
        if let persistedHelper = try values.decodeIfPresent(Bool.self, forKey: .isInternalHelper) {
            isInternalHelper = persistedHelper
        } else {
            let helperProvider = provider
            let helperTask = task
            let matchedRecentEvent = recentEvents.contains { event in
                event.task.map { AgentTaskTitle.isInternalHelper($0, provider: helperProvider) } == true
            }
            isInternalHelper = AgentTaskTitle.isInternalHelper(helperTask, provider: helperProvider)
                || matchedRecentEvent
        }
        reconcilePlanWithTerminalState(at: completedAt ?? updatedAt)
    }
}

private extension AgentEvent {
    var isGrokWorkflowState: Bool {
        metadata?["hookEvent"] == "grokWorkflowState"
    }

    var hasOfficialSessionTitle: Bool {
        metadata?["titleSource"] == "session"
    }

    var explicitlyResumesSession: Bool {
        if type == .started { return true }
        guard let hookEvent = metadata?["hookEvent"] else { return false }
        return HookEventName(rawEventName: hookEvent)?.resumesSession == true
    }
}
