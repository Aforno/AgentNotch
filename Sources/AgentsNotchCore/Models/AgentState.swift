import Foundation

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case idle
    case starting
    case thinking
    case running
    case executingTool
    case editing
    case waitingForUser
    /// Cold-start uncertainty: the session was active when the app last quit,
    /// but hooks alone cannot prove the provider process is still working.
    case unknown
    case completed
    case failed

    public var isActive: Bool {
        switch self {
        case .starting, .thinking, .running, .executingTool, .editing, .waitingForUser, .unknown:
            true
        case .idle, .completed, .failed:
            false
        }
    }

    public var needsAttention: Bool {
        self == .waitingForUser || self == .failed
    }

    public var displayName: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting"
        case .thinking: "Thinking"
        case .running: "Running"
        case .executingTool: "Using tool"
        case .editing: "Editing"
        case .waitingForUser: "Needs attention"
        case .unknown: "Reconnecting"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}
