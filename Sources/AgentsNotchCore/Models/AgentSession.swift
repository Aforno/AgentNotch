import Foundation

public struct AgentSession: Codable, Identifiable, Hashable, Sendable {
    public let id: String
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
        parentSessionId = event.parentSessionId
        agentRole = event.agentRole
        plan = event.plan
        workflows = []
        applyWorkflowUpdate(event.workflowUpdate, at: event.timestamp)
    }

    public var isActive: Bool { state.isActive }
    public var needsAttention: Bool { state.needsAttention }
    public var isSubagent: Bool { parentSessionId != nil }

    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Bool {
        let isTerminal = state == .completed || state == .failed
        let isLateWaitingNotification = isTerminal && event.resolvedState == .waitingForUser
        let advancesCurrentState = event.timestamp >= updatedAt && !isLateWaitingNotification
        if advancesCurrentState {
            provider = event.provider
            if let task = event.task?.nonEmpty { self.task = task }
            if let activity = event.activity?.nonEmpty { currentActivity = activity }
            state = event.resolvedState
            updatedAt = event.timestamp
            // Treat empty/whitespace cwd as absent so hook defaults of "" cannot
            // wipe a previously stored absolute path.
            if let directory = event.workingDirectory?.nonEmpty {
                workingDirectory = directory
            }
            applicationURL = event.applicationURL ?? applicationURL
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
        } else if task == "Untitled task", let task = event.task?.nonEmpty {
            self.task = task
        }

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

        recentEvents.append(event)
        recentEvents.sort { $0.timestamp > $1.timestamp }
        recentEvents = Array(recentEvents.prefix(10))
        return advancesCurrentState
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

    private enum CodingKeys: String, CodingKey {
        case id, provider, task, currentActivity, state, startedAt, updatedAt, completedAt
        case workingDirectory, recentFiles, recentEvents, applicationURL
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
        recentFiles = try values.decode([String].self, forKey: .recentFiles)
        recentEvents = try values.decode([AgentEvent].self, forKey: .recentEvents)
        applicationURL = try values.decodeIfPresent(URL.self, forKey: .applicationURL)
        parentSessionId = try values.decodeIfPresent(String.self, forKey: .parentSessionId)
        agentRole = try values.decodeIfPresent(String.self, forKey: .agentRole)
        plan = try values.decodeIfPresent(AgentPlan.self, forKey: .plan)
        workflows = try values.decodeIfPresent([AgentWorkflow].self, forKey: .workflows) ?? []
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
