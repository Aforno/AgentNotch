import Foundation

public struct GrokSessionContext: Sendable {
    public let parentSessionId: String?
    public let agentRole: String?
    public let workflowOwnerSessionId: String?
    public let workflowTask: String?
    public let workflowPhase: String?
    public let workflowState: AgentState?
    public let workflowUpdate: AgentWorkflowUpdate?
    public let workflowUpdatedAt: Date?

    public func workflowEvent(now: Date, workingDirectory: String?) -> AgentEvent? {
        guard let owner = workflowOwnerSessionId,
              let state = workflowState,
              let update = workflowUpdate else { return nil }
        return AgentEvent(
            type: .activity,
            sessionId: "\(AgentProvider.grok.rawValue):\(owner)",
            provider: .grok,
            task: workflowTask,
            activity: workflowPhase.map { "Workflow · \($0)" } ?? "Workflow \(update.status?.displayName ?? "Running")",
            state: state,
            timestamp: now,
            workingDirectory: workingDirectory,
            metadata: ["hookEvent": "grokWorkflowState"],
            workflowUpdate: update
        )
    }
}

public enum GrokSessionContextResolver {
    public static func resolve(
        _ payload: AgentHookPayload,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> GrokSessionContext {
        resolve(
            sessionId: payload.sessionId,
            workspacePaths: [payload.workspaceRoot, payload.cwd],
            fallbackParent: payload.parentSessionId,
            fallbackRole: payload.description ?? payload.agentType,
            grokHome: grokHome
        )
    }

    public static func resolve(
        sessionId: String,
        workspaceRoot: String,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) -> GrokSessionContext {
        resolve(
            sessionId: sessionId,
            workspacePaths: [workspaceRoot],
            fallbackParent: nil,
            fallbackRole: nil,
            grokHome: grokHome
        )
    }

    private static func resolve(
        sessionId: String,
        workspacePaths: [String?],
        fallbackParent: String?,
        fallbackRole: String?,
        grokHome: URL
    ) -> GrokSessionContext {
        guard isSafePathComponent(sessionId) else {
            return GrokSessionContext(
                parentSessionId: fallbackParent,
                agentRole: fallbackRole,
                workflowOwnerSessionId: nil,
                workflowTask: nil,
                workflowPhase: nil,
                workflowState: nil,
                workflowUpdate: nil,
                workflowUpdatedAt: nil
            )
        }
        let fileManager = FileManager.default
        let paths = workspacePaths
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seenPaths = Set<String>()

        for workspacePath in paths where seenPaths.insert(workspacePath).inserted {
            let bucket = grokHome
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(encodedWorkspacePath(workspacePath), isDirectory: true)
            guard fileManager.fileExists(atPath: bucket.path) else { continue }

            // Prefer the session's own directory. Top-level (non-child) sessions
            // are the common PreToolUse/PostToolUse path; resolving them must
            // not list every peer session and probe subagents/*/meta.json.
            let ownDirectory = bucket.appendingPathComponent(sessionId, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: ownDirectory.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                if let workflow = latestWorkflow(in: ownDirectory, fileManager: fileManager) {
                    return context(parent: nil, role: nil, owner: sessionId, workflow: workflow)
                }
                return GrokSessionContext(
                    parentSessionId: fallbackParent,
                    agentRole: fallbackRole,
                    workflowOwnerSessionId: nil,
                    workflowTask: nil,
                    workflowPhase: nil,
                    workflowState: nil,
                    workflowUpdate: nil,
                    workflowUpdatedAt: nil
                )
            }

            guard let sessionDirectories = try? fileManager.contentsOfDirectory(
                at: bucket,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            if let resolved = resolveChild(
                sessionId: sessionId,
                bucket: bucket,
                sessionDirectories: sessionDirectories
            ) {
                return resolved
            }
        }

        return GrokSessionContext(
            parentSessionId: fallbackParent,
            agentRole: fallbackRole,
            workflowOwnerSessionId: nil,
            workflowTask: nil,
            workflowPhase: nil,
            workflowState: nil,
            workflowUpdate: nil,
            workflowUpdatedAt: nil
        )
    }

    private static func resolveChild(
        sessionId: String,
        bucket: URL,
        sessionDirectories: [URL]
    ) -> GrokSessionContext? {
        let decoder = JSONDecoder()
        for parentDirectory in sessionDirectories {
            let metadataURL = parentDirectory
                .appendingPathComponent("subagents", isDirectory: true)
                .appendingPathComponent(sessionId, isDirectory: true)
                .appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metadataURL),
                  let metadata = try? decoder.decode(SubagentMetadata.self, from: data)
            else { continue }

            let workflow = latestWorkflow(in: parentDirectory, fileManager: .default)
            return context(
                parent: metadata.parentSessionId,
                role: metadata.description ?? metadata.subagentType,
                owner: metadata.parentSessionId,
                workflow: workflow
            )
        }
        return nil
    }

    private static func context(
        parent: String?,
        role: String?,
        owner: String?,
        workflow: StoredWorkflowSnapshot?
    ) -> GrokSessionContext {
        let state = workflow?.state
        return GrokSessionContext(
            parentSessionId: parent,
            agentRole: role,
            workflowOwnerSessionId: workflow == nil ? nil : owner,
            workflowTask: state?.objective ?? state?.name,
            workflowPhase: state?.currentPhase,
            workflowState: state.map(agentState),
            workflowUpdate: state.map(workflowUpdate),
            workflowUpdatedAt: workflow?.updatedAt
        )
    }

    private static func latestWorkflow(
        in sessionDirectory: URL,
        fileManager: FileManager
    ) -> StoredWorkflowSnapshot? {
        let workflowsDirectory = sessionDirectory.appendingPathComponent("workflows", isDirectory: true)
        guard let runDirectories = try? fileManager.contentsOfDirectory(
            at: workflowsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let decoder = JSONDecoder()
        return runDirectories
            .compactMap { directory -> StoredWorkflowSnapshot? in
                let stateURL = directory.appendingPathComponent("state.json")
                guard let data = try? Data(contentsOf: stateURL),
                      let state = try? decoder.decode(WorkflowEnvelope.self, from: data).state
                else { return nil }
                let modified = (try? stateURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return StoredWorkflowSnapshot(state: state, updatedAt: modified)
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private static func workflowUpdate(_ workflow: StoredWorkflow) -> AgentWorkflowUpdate {
        let currentIndex = workflow.phases.firstIndex { $0.title == workflow.currentPhase }
        let steps = workflow.phases.enumerated().map { index, phase in
            AgentStep(
                id: "\(workflow.runId):phase:\(index)",
                title: phase.title,
                status: phaseStatus(workflow: workflow, index: index, currentIndex: currentIndex)
            )
        }
        return AgentWorkflowUpdate(
            id: workflow.runId,
            title: workflow.name,
            status: workflowStatus(workflow.status),
            steps: steps
        )
    }

    private static func phaseStatus(
        workflow: StoredWorkflow,
        index: Int,
        currentIndex: Int?
    ) -> AgentStepStatus {
        if workflowStatus(workflow.status) == .completed { return .completed }
        guard let currentIndex else { return .pending }
        if index < currentIndex { return .completed }
        if index > currentIndex { return .pending }
        switch workflowStatus(workflow.status) {
        case .failed: return .failed
        case .blocked: return .blocked
        case .waiting: return .blocked
        default: return .inProgress
        }
    }

    private static func workflowStatus(_ status: String) -> AgentWorkflowStatus {
        switch status.lowercased() {
        case "completed", "complete", "done": .completed
        case "failed", "error": .failed
        case "blocked", "cancelled", "canceled", "interrupted": .blocked
        case "waiting", "paused": .waiting
        case "pending": .pending
        default: .running
        }
    }

    private static func agentState(_ workflow: StoredWorkflow) -> AgentState {
        switch workflowStatus(workflow.status) {
        case .completed: .completed
        case .failed: .failed
        case .blocked, .waiting: .waitingForUser
        case .pending: .starting
        case .running: .running
        }
    }

    private static func encodedWorkspacePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? path
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains("\0")
    }
}

private struct SubagentMetadata: Decodable {
    let parentSessionId: String
    let subagentType: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case parentSessionId = "parent_session_id"
        case subagentType = "subagent_type"
        case description
    }
}

private struct WorkflowEnvelope: Decodable {
    let state: StoredWorkflow
}

private struct StoredWorkflowSnapshot {
    let state: StoredWorkflow
    let updatedAt: Date
}

private struct StoredWorkflow: Decodable {
    let runId: String
    let name: String
    let objective: String?
    let status: String
    let phases: [StoredWorkflowPhase]
    let currentPhase: String?

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case name, objective, status, phases
        case currentPhase = "current_phase"
    }
}

private struct StoredWorkflowPhase: Decodable {
    let title: String
}
