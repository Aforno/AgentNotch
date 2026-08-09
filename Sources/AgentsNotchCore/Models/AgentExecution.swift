import Foundation

public enum AgentStepStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case blocked

    public var displayName: String {
        switch self {
        case .pending: "Pending"
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .failed: "Failed"
        case .blocked: "Blocked"
        }
    }

    public var isFinished: Bool {
        switch self {
        case .completed, .failed, .blocked: true
        case .pending, .inProgress: false
        }
    }
}

public struct AgentStep: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: AgentStepStatus

    public init(id: String, title: String, status: AgentStepStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
}

public struct AgentPlan: Codable, Hashable, Sendable {
    public var title: String?
    public var explanation: String?
    public var steps: [AgentStep]
    public var updatedAt: Date

    public init(
        title: String? = nil,
        explanation: String? = nil,
        steps: [AgentStep],
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.explanation = explanation
        self.steps = steps
        self.updatedAt = updatedAt
    }

    public var completedStepCount: Int {
        steps.filter { $0.status == .completed }.count
    }

    public var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(completedStepCount) / Double(steps.count)
    }

    public var isComplete: Bool {
        !steps.isEmpty && steps.allSatisfy { $0.status == .completed }
    }

    mutating func completeUnfinishedSteps(at timestamp: Date) {
        var changed = false
        for index in steps.indices {
            switch steps[index].status {
            case .pending, .inProgress:
                steps[index].status = .completed
                changed = true
            case .completed, .failed, .blocked:
                break
            }
        }
        if changed {
            updatedAt = max(updatedAt, timestamp)
        }
    }
}

public enum AgentWorkflowStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case waiting
    case completed
    case failed
    case blocked

    public var displayName: String {
        switch self {
        case .pending: "Pending"
        case .running: "Running"
        case .waiting: "Waiting"
        case .completed: "Completed"
        case .failed: "Failed"
        case .blocked: "Blocked"
        }
    }

    public var isActive: Bool {
        switch self {
        case .pending, .running, .waiting: true
        case .completed, .failed, .blocked: false
        }
    }
}

public struct AgentWorkflow: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: AgentWorkflowStatus
    public var steps: [AgentStep]
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        status: AgentWorkflowStatus,
        steps: [AgentStep] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.steps = steps
        self.updatedAt = updatedAt
    }
}

/// A partial workflow mutation carried by an event. Optional fields let a
/// provider report lifecycle changes without repeatedly sending the full run.
public struct AgentWorkflowUpdate: Codable, Hashable, Sendable {
    public var id: String
    public var title: String?
    public var status: AgentWorkflowStatus?
    public var steps: [AgentStep]?

    public init(
        id: String,
        title: String? = nil,
        status: AgentWorkflowStatus? = nil,
        steps: [AgentStep]? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.steps = steps
    }
}
