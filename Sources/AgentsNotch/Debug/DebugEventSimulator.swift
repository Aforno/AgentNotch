#if DEBUG
import AgentsNotchCore
import Foundation

@MainActor
final class DebugEventSimulator {
    private static let sessionPrefix = "debug-simulator:"
    private static let legacySessionIDs: Set<String> = [
        "simulator-primary",
        "sim-codex",
        "sim-claude",
        "sim-gemini",
        "sim-codex:reviewer",
    ]

    private let activity: AgentActivityService
    private var demoTask: Task<Void, Never>?

    init(activity: AgentActivityService) {
        self.activity = activity
    }

    static func isSimulated(_ session: AgentSession) -> Bool {
        session.id.hasPrefix(sessionPrefix)
            || legacySessionIDs.contains(session.id)
            || session.recentEvents.contains { $0.metadata?["source"] == "simulator" }
    }

    func reset() {
        demoTask?.cancel()
        demoTask = nil
        let simulatedIDs = Set(activity.sessions.filter(Self.isSimulated).map(\.id))
        activity.removeSessions(ids: simulatedIDs)
    }

    func simulate(_ state: AgentState) {
        ingest(event(
            for: state,
            sessionId: Self.id("state"),
            task: "Refine authentication flow"
        ))
    }

    func simulatePlan() {
        ingest(AgentEvent(
            type: .activity,
            sessionId: Self.id("plan"),
            provider: .codex,
            task: "Add regression tests and run suite",
            activity: "Running regression tests",
            state: .running,
            workingDirectory: "/Users/demo/AgentsNotch",
            plan: AgentPlan(
                steps: [
                    AgentStep(
                        id: "attention-fallback",
                        title: "Fix multi-session attention fallback + restore on load",
                        status: .completed
                    ),
                    AgentStep(
                        id: "serialized-saves",
                        title: "Serialize session persistence saves",
                        status: .completed
                    ),
                    AgentStep(
                        id: "regression-suite",
                        title: "Add regression tests and run suite",
                        status: .inProgress
                    ),
                ]
            )
        ))
    }

    func simulateWorkflow() {
        ingest(AgentEvent(
            type: .activity,
            sessionId: Self.id("workflow"),
            provider: .codex,
            task: "Prepare release workflow",
            activity: "Verifying release artifacts",
            state: .executingTool,
            workingDirectory: "/Users/demo/AgentsNotch",
            workflowUpdate: AgentWorkflowUpdate(
                id: "release",
                title: "Release Agents Notch",
                status: .running,
                steps: [
                    AgentStep(id: "build", title: "Build universal app", status: .completed),
                    AgentStep(id: "test", title: "Run regression suite", status: .completed),
                    AgentStep(id: "package", title: "Package application", status: .inProgress),
                    AgentStep(id: "verify", title: "Verify launch", status: .pending),
                ]
            )
        ))
    }

    func simulateSubagents() {
        let parentID = Self.id("orchestrator")
        ingest(AgentEvent(
            type: .activity,
            sessionId: parentID,
            provider: .codex,
            task: "Coordinate implementation review",
            activity: "Waiting for subagents",
            state: .running,
            workingDirectory: "/Users/demo/AgentsNotch"
        ))
        ingest(AgentEvent(
            type: .activity,
            sessionId: Self.id("orchestrator:implementer"),
            provider: .codex,
            task: "Implement plan presentation",
            activity: "Editing AgentExecutionView.swift",
            state: .editing,
            workingDirectory: "/Users/demo/AgentsNotch",
            parentSessionId: parentID,
            agentRole: "implementer"
        ))
        ingest(AgentEvent(
            type: .waiting,
            sessionId: Self.id("orchestrator:reviewer"),
            provider: .codex,
            task: "Review simulator lifecycle",
            activity: "Needs review decision",
            state: .waitingForUser,
            workingDirectory: "/Users/demo/AgentsNotch",
            parentSessionId: parentID,
            agentRole: "reviewer"
        ))
    }

    func runConcurrentDemo() {
        demoTask?.cancel()
        demoTask = Task { [weak self] in
            guard let self else { return }
            let sessions = [
                (Self.id("codex"), AgentProvider.codex, "Ship Agents Notch"),
                (Self.id("claude"), AgentProvider.claudeCode, "Review pull request"),
                (Self.id("gemini"), AgentProvider.geminiCLI, "Investigate test failure"),
            ]

            for (id, provider, task) in sessions {
                ingest(AgentEvent(
                    type: .started,
                    sessionId: id,
                    provider: provider,
                    task: task,
                    activity: "Starting",
                    state: .starting,
                    workingDirectory: "/Users/demo/\(task.replacingOccurrences(of: " ", with: "-"))"
                ))
            }
            simulatePlan()
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }

            ingest(event(for: .executingTool, sessionId: Self.id("codex"), task: nil))
            ingest(AgentEvent(
                type: .activity,
                sessionId: Self.id("claude"),
                provider: .claudeCode,
                activity: "Reviewing AppDelegate.swift",
                state: .thinking
            ))
            ingest(AgentEvent(
                type: .waiting,
                sessionId: Self.id("gemini"),
                provider: .geminiCLI,
                activity: "Waiting for input",
                state: .waitingForUser
            ))
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            ingest(event(for: .editing, sessionId: Self.id("codex"), task: nil))
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            ingest(event(for: .completed, sessionId: Self.id("codex"), task: nil))
        }
    }

    private func ingest(_ sourceEvent: AgentEvent) {
        var event = sourceEvent
        event.metadata = (event.metadata ?? [:]).merging(
            ["source": "simulator"],
            uniquingKeysWith: { _, new in new }
        )
        activity.ingest(event)
    }

    private func event(for state: AgentState, sessionId: String, task: String?) -> AgentEvent {
        let values: (AgentEventType, String, String?) = switch state {
        case .idle: (.activity, "Idle", nil)
        case .starting: (.started, "Starting session", nil)
        case .thinking: (.activity, "Thinking through changes", nil)
        case .running: (.activity, "Running tests", nil)
        case .executingTool: (.toolStarted, "Running swift test", nil)
        case .editing: (.fileChanged, "Editing AuthService.swift", "Sources/AuthService.swift")
        case .waitingForUser: (.waiting, "Needs approval", nil)
        case .unknown: (.activity, "Reconnecting after restart", nil)
        case .completed: (.completed, "Tests passed", nil)
        case .failed: (.failed, "Build failed", nil)
        }
        return AgentEvent(
            type: values.0,
            sessionId: sessionId,
            provider: .codex,
            task: task,
            activity: values.1,
            state: state,
            workingDirectory: "/Users/demo/AgentsNotch",
            file: values.2
        )
    }

    private static func id(_ suffix: String) -> String {
        sessionPrefix + suffix
    }
}
#endif
