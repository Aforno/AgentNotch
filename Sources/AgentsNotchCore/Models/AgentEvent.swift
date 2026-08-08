import Foundation

public enum AgentEventType: String, Codable, CaseIterable, Sendable {
    case started = "agent.started"
    case activity = "agent.activity"
    case toolStarted = "agent.tool.started"
    case toolCompleted = "agent.tool.completed"
    case fileChanged = "agent.file.changed"
    case waiting = "agent.waiting"
    case completed = "agent.completed"
    case failed = "agent.failed"
}

public struct AgentEvent: Codable, Identifiable, Hashable, Sendable {
    public var protocolVersion: Int
    public var id: UUID
    public var type: AgentEventType
    public var sessionId: String
    public var provider: AgentProvider
    public var task: String?
    public var activity: String?
    public var state: AgentState?
    public var timestamp: Date
    public var workingDirectory: String?
    public var file: String?
    public var applicationURL: URL?
    public var metadata: [String: String]?
    public var parentSessionId: String?
    public var agentRole: String?
    public var plan: AgentPlan?
    public var workflowUpdate: AgentWorkflowUpdate?

    public init(
        protocolVersion: Int = 1,
        id: UUID = UUID(),
        type: AgentEventType,
        sessionId: String,
        provider: AgentProvider,
        task: String? = nil,
        activity: String? = nil,
        state: AgentState? = nil,
        timestamp: Date = Date(),
        workingDirectory: String? = nil,
        file: String? = nil,
        applicationURL: URL? = nil,
        metadata: [String: String]? = nil,
        parentSessionId: String? = nil,
        agentRole: String? = nil,
        plan: AgentPlan? = nil,
        workflowUpdate: AgentWorkflowUpdate? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.type = type
        self.sessionId = sessionId
        self.provider = provider
        self.task = task
        self.activity = activity
        self.state = state
        self.timestamp = timestamp
        self.workingDirectory = workingDirectory
        self.file = file
        self.applicationURL = applicationURL
        self.metadata = metadata
        self.parentSessionId = parentSessionId
        self.agentRole = agentRole
        self.plan = plan
        self.workflowUpdate = workflowUpdate
    }

    public var resolvedState: AgentState {
        if let state { return state }
        return switch type {
        case .started: .starting
        case .activity: .running
        case .toolStarted: .executingTool
        case .toolCompleted: .running
        case .fileChanged: .editing
        case .waiting: .waitingForUser
        case .completed: .completed
        case .failed: .failed
        }
    }
}

public extension JSONEncoder {
    static var agentsNotch: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            try container.encode(date.formatted(style))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var agentsNotch: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 timestamp")
        }
        return decoder
    }
}
