import AgentsNotchCore
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppRuntime {
    enum SelfTestStatus: Equatable {
        case idle
        case running
        case passed(Date)
        case failed(String)
    }

    let activity: AgentActivityService
    let codexIntegration: ProviderIntegrationManager
    let claudeIntegration: ProviderIntegrationManager
    let grokIntegration: ProviderIntegrationManager
    let geminiIntegration: ProviderIntegrationManager
    let openCodeIntegration: ProviderIntegrationManager
    let cursorIntegration: ProviderIntegrationManager
    let providerAdapters: [HookProviderAdapter]
    let notifications: AgentNotificationService
    let updates: UpdateService
    #if DEBUG
    let simulator: DebugEventSimulator
    #endif

    private(set) var socketStatus = "Starting"
    private(set) var socketError: String?
    private(set) var persistenceError: String?
    private(set) var lastEventReceivedAt: [AgentProvider: Date] = [:]
    private(set) var requestedSessionID: String?
    private(set) var selfTestStatuses: [AgentProvider: SelfTestStatus] = [:]
    var openActivityCenterHandler: (() -> Void)?
    var openOnboardingHandler: (() -> Void)?
    var openSettingsHandler: (() -> Void)?
    weak var panelController: NotchPanelController?

    private let persistence: SessionPersistence
    private let socketURL: URL
    private let monitorProviders: Bool
    private let grokHome: URL
    private let historyRetentionDays: () -> Int?
    private let originActivation = OriginActivationService()
    private var socketServer: UnixSocketServer?
    /// Coalesces rapid session writes so an older snapshot cannot overwrite a newer one.
    private var persistTask: Task<Void, Never>?
    /// Completes sessions still in `.unknown` when no live hook confirms them.
    private var unknownGraceTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var acceptsEvents = false
    private var isRestoring = false
    private var startupEvents: [AgentEvent] = []

    /// How long restored unverified runners stay in `.unknown` before the app
    /// assumes they ended without a hook. Live events cancel this per session.
    static let unknownSessionGracePeriod: Duration = .seconds(90)

    init(
        persistence: SessionPersistence = SessionPersistence(),
        socketURL: URL = AgentSocketLocation.defaultURL,
        monitorProviders: Bool = true,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok"),
        providerHomeDirectoryURL: URL? = nil,
        bundledRelayURL: URL? = nil,
        historyRetentionDays: @escaping () -> Int? = {
            UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int
        }
    ) {
        self.persistence = persistence
        self.socketURL = socketURL
        self.monitorProviders = monitorProviders
        self.grokHome = grokHome
        self.historyRetentionDays = historyRetentionDays
        activity = AgentActivityService()
        codexIntegration = ProviderIntegrationManager(
            provider: .codex,
            homeDirectoryURL: providerHomeDirectoryURL,
            bundledRelayURL: bundledRelayURL
        )
        claudeIntegration = ProviderIntegrationManager(
            provider: .claudeCode,
            homeDirectoryURL: providerHomeDirectoryURL,
            bundledRelayURL: bundledRelayURL
        )
        grokIntegration = ProviderIntegrationManager(
            provider: .grok,
            homeDirectoryURL: providerHomeDirectoryURL,
            bundledRelayURL: bundledRelayURL
        )
        geminiIntegration = ProviderIntegrationManager(
            provider: .geminiCLI,
            homeDirectoryURL: providerHomeDirectoryURL,
            bundledRelayURL: bundledRelayURL
        )
        openCodeIntegration = ProviderIntegrationManager(
            provider: .openCode,
            homeDirectoryURL: providerHomeDirectoryURL,
            bundledRelayURL: bundledRelayURL
        )
        cursorIntegration = ProviderIntegrationManager(
            provider: .cursor,
            homeDirectoryURL: providerHomeDirectoryURL,
            bundledRelayURL: bundledRelayURL
        )
        providerAdapters = [
            codexIntegration,
            claudeIntegration,
            grokIntegration,
            geminiIntegration,
            openCodeIntegration,
            cursorIntegration,
        ]
            .map(HookProviderAdapter.init)
        notifications = AgentNotificationService()
        updates = UpdateService()
        #if DEBUG
        simulator = DebugEventSimulator(activity: activity)
        #endif
        notifications.onOpenSession = { [weak self] sessionID in
            self?.presentSession(sessionID)
        }
    }

    func start() async {
        guard !acceptsEvents else { return }
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        acceptsEvents = true
        isRestoring = true
        startupEvents.removeAll(keepingCapacity: true)

        // Bind before any awaited restore work. Hooks emitted during startup are
        // buffered and replayed after the persisted snapshot is installed.
        let server = UnixSocketServer(socketURL: socketURL) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.receive(event, generation: generation)
            }
        }
        do {
            try server.start()
            socketServer = server
            socketStatus = "Listening"
            socketError = nil
        } catch {
            socketStatus = "Unavailable"
            socketError = error.localizedDescription
        }

        let loadResult = await persistence.load()
        guard acceptsEvents, generation == lifecycleGeneration else { return }
        let saved = loadResult.sessions
        persistenceError = loadResult.recoveryMessage
        activity.replaceSessions(saved)
        // Do not invent completion for restored runners. Dead origin PIDs are
        // completed; everything else becomes `.unknown` until a live hook or
        // the reconnect grace period resolves them. Waiting rows stay waiting.
        activity.reconcileUnverifiedActiveSessions()
        reconcileGrokSessionContext()
        pruneHistory()
        #if DEBUG
        // Simulator state is intentionally ephemeral. This also removes rows
        // written by older debug builds before simulator persistence was split.
        simulator.reset()
        #endif
        // Always save the reconciled snapshot. This persists restored Grok
        // relationships and recreates a clean file after corruption recovery.
        let saveError = await persistence.save(persistableSessions)
        guard acceptsEvents, generation == lifecycleGeneration else { return }
        if let error = saveError {
            persistenceError = error
        }
        activity.onSessionsChanged = { [weak self] _ in
            self?.schedulePersist()
        }
        isRestoring = false
        let bufferedEvents = startupEvents
        startupEvents.removeAll(keepingCapacity: true)
        for event in bufferedEvents {
            process(event, notify: false)
        }
        scheduleUnknownSessionGracePeriod(generation: generation)

        if monitorProviders {
            for adapter in providerAdapters {
                guard acceptsEvents, generation == lifecycleGeneration else { return }
                try? await adapter.startMonitoring()
            }
        }
        updates.checkAutomaticallyIfNeeded()
    }

    func stop() {
        lifecycleGeneration += 1
        acceptsEvents = false
        isRestoring = false
        startupEvents.removeAll()
        activity.onSessionsChanged = nil
        unknownGraceTask?.cancel()
        unknownGraceTask = nil
        persistTask?.cancel()
        persistTask = nil
        do {
            try persistence.saveSynchronously(persistableSessions)
        } catch {
            persistenceError = "Could not save session history: \(error.localizedDescription)"
        }
        socketServer?.stop()
        socketServer = nil
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Yield so a burst of ingests collapses into one write of the latest state.
            await Task.yield()
            guard !Task.isCancelled else { return }
            if let error = await persistence.save(persistableSessions) {
                persistenceError = error
            }
        }
    }

    private func receive(_ event: AgentEvent, generation: Int) {
        guard acceptsEvents, generation == lifecycleGeneration else { return }
        if isRestoring {
            startupEvents.append(event)
        } else {
            process(event, notify: true)
        }
    }

    private func process(_ event: AgentEvent, notify: Bool) {
        let previousState = activity.sessions.first { $0.id == event.sessionId }?.state
        activity.ingest(event)
        pruneHistory()
        if event.metadata?["source"] != "self-test" {
            lastEventReceivedAt[event.provider] = Date()
            integration(for: event.provider)?.noteEventReceived()
        }
        guard let session = activity.sessions.first(where: { $0.id == event.sessionId }) else { return }

        if session.state == .waitingForUser, previousState != .waitingForUser, notify {
            notifications.deliverAttention(for: session, waitingCount: activity.attentionCount)
        } else if session.state == .failed, previousState != .failed, notify {
            notifications.deliverFailure(for: session)
        } else if previousState == .waitingForUser, session.state != .waitingForUser {
            notifications.removeNotification(for: session.id)
        }
    }

    private func scheduleUnknownSessionGracePeriod(generation: Int) {
        unknownGraceTask?.cancel()
        guard activity.sessions.contains(where: { $0.state == .unknown }) else {
            unknownGraceTask = nil
            return
        }
        unknownGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.unknownSessionGracePeriod)
            guard let self,
                  !Task.isCancelled,
                  self.acceptsEvents,
                  generation == self.lifecycleGeneration
            else { return }
            self.activity.completeUnknownSessions()
        }
    }

    private func reconcileGrokSessionContext() {
        let grokPrefix = "\(AgentProvider.grok.rawValue):"
        var workflowContexts: [String: GrokSessionContext] = [:]

        for session in activity.sessions where session.provider == .grok {
            guard session.id.hasPrefix(grokPrefix),
                  let workspace = session.workingDirectory else { continue }
            let nativeSessionID = String(session.id.dropFirst(grokPrefix.count))
            let context = GrokSessionContextResolver.resolve(
                sessionId: nativeSessionID,
                workspaceRoot: workspace,
                grokHome: grokHome
            )

            if let parent = context.parentSessionId {
                activity.ingest(AgentEvent(
                    type: .activity,
                    sessionId: session.id,
                    provider: .grok,
                    activity: session.currentActivity,
                    state: session.state,
                    timestamp: session.updatedAt,
                    workingDirectory: session.workingDirectory,
                    parentSessionId: "\(grokPrefix)\(parent)",
                    agentRole: context.agentRole
                ))
            }
            if let owner = context.workflowOwnerSessionId {
                workflowContexts[owner] = context
            }
        }

        for context in workflowContexts.values {
            guard let workflowUpdatedAt = context.workflowUpdatedAt,
                  var event = context.workflowEvent(now: workflowUpdatedAt, workingDirectory: nil)
            else {
                continue
            }
            if let session = activity.sessions.first(where: { $0.id == event.sessionId }) {
                if session.state == .unknown {
                    // On-disk Grok workflow status is stronger evidence than
                    // cold-start uncertainty: complete finished runs and restore
                    // active ones instead of inventing a generic completion.
                    activity.applyRestoredLifecycle(
                        sessionId: session.id,
                        state: event.resolvedState,
                        activity: event.activity,
                        at: workflowUpdatedAt
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

    private var persistableSessions: [AgentSession] {
        #if DEBUG
        activity.sessions.filter { !DebugEventSimulator.isSimulated($0) && !Self.isSelfTest($0) }
        #else
        activity.sessions.filter { !Self.isSelfTest($0) }
        #endif
    }

    private static func isSelfTest(_ session: AgentSession) -> Bool {
        session.recentEvents.contains { $0.metadata?["source"] == "self-test" }
    }

    func open(_ session: AgentSession) {
        originActivation.open(session)
    }

    func openFile(_ path: String) {
        originActivation.openFile(path)
    }

    func presentSession(_ sessionID: String) {
        guard activity.sessions.contains(where: { $0.id == sessionID }) else { return }
        requestedSessionID = sessionID
        if panelController?.isSurfaceEnabled == true {
            panelController?.show()
        } else {
            openActivityCenter()
        }
    }

    func consumeRequestedSession(_ sessionID: String) {
        guard requestedSessionID == sessionID else { return }
        requestedSessionID = nil
    }

    func runSelfTest(for provider: AgentProvider) {
        guard selfTestStatuses[provider] != .running else { return }
        guard let integration = integration(for: provider) else {
            selfTestStatuses[provider] = .failed("This provider does not support relay self-tests.")
            return
        }
        integration.prepareForMonitoring()
        guard !integration.status.canInstall else {
            selfTestStatuses[provider] = .failed(
                integration.lastError ?? "Install the provider hooks before testing the relay."
            )
            return
        }

        selfTestStatuses[provider] = .running
        let nativeSessionID = "self-test:\(UUID().uuidString)"
        let sessionID = "\(provider.rawValue):\(nativeSessionID)"
        let payload: Data
        do {
            payload = try relaySelfTestPayload(provider: provider, sessionID: nativeSessionID)
        } catch {
            selfTestStatuses[provider] = .failed(error.localizedDescription)
            return
        }
        let executableURL = integration.installedRelayURL
        let socketURL = socketURL

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.detached {
                    try RelaySelfTestRunner.run(
                        executableURL: executableURL,
                        provider: provider,
                        socketURL: socketURL,
                        payload: payload
                    )
                }.value
                for _ in 0..<20 {
                    if activity.sessions.contains(where: { $0.id == sessionID }) {
                        activity.removeSession(id: sessionID)
                        selfTestStatuses[provider] = .passed(Date())
                        return
                    }
                    try await Task.sleep(for: .milliseconds(50))
                }
                selfTestStatuses[provider] = .failed("The installed relay did not deliver the test event.")
            } catch {
                selfTestStatuses[provider] = .failed(error.localizedDescription)
            }
        }
    }

    func clearHistory() {
        activity.clearRecent()
    }

    func applyHistoryRetention(days: Int) {
        guard days > 0 else { return }
        activity.pruneCompleted(olderThan: TimeInterval(days * 24 * 60 * 60))
    }

    func refreshNotchSurface() {
        panelController?.refreshPreferences()
    }

    func openActivityCenter() {
        openActivityCenterHandler?()
    }

    func openOnboarding() {
        openOnboardingHandler?()
    }

    func openSettings() {
        openSettingsHandler?()
    }

    private func pruneHistory() {
        guard let configuredDays = historyRetentionDays(), configuredDays > 0 else { return }
        let days = max(1, configuredDays)
        activity.pruneCompleted(olderThan: TimeInterval(days * 24 * 60 * 60))
    }

    private func integration(for provider: AgentProvider) -> ProviderIntegrationManager? {
        switch provider {
        case .codex: codexIntegration
        case .claudeCode: claudeIntegration
        case .grok: grokIntegration
        case .geminiCLI: geminiIntegration
        case .openCode: openCodeIntegration
        case .cursor: cursorIntegration
        default: nil
        }
    }

    private func relaySelfTestPayload(provider: AgentProvider, sessionID: String) throws -> Data {
        let hookEventName = switch provider {
        case .geminiCLI: "BeforeAgent"
        case .grok: "user_prompt_submit"
        case .cursor: "beforeSubmitPrompt"
        default: "UserPromptSubmit"
        }
        var object: [String: Any] = [
            "session_id": sessionID,
            "cwd": FileManager.default.homeDirectoryForCurrentUser.path,
            "hook_event_name": hookEventName,
            "prompt": "Connection self-test",
        ]
        if provider == .cursor {
            object["conversation_id"] = object.removeValue(forKey: "session_id")
            object["workspace_roots"] = [object.removeValue(forKey: "cwd") as? String].compactMap { $0 }
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}

private enum RelaySelfTestRunner {
    static func run(
        executableURL: URL,
        provider: AgentProvider,
        socketURL: URL,
        payload: Data
    ) throws {
        let process = Process()
        let input = Pipe()
        let completed = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = [
            "--provider", provider.rawValue,
            "--socket", socketURL.path,
            "--self-test",
        ]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completed.signal() }

        try process.run()
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()

        guard completed.wait(timeout: .now() + 3) == .success else {
            process.terminate()
            throw RelaySelfTestError.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw RelaySelfTestError.failed(process.terminationStatus)
        }
    }
}

private enum RelaySelfTestError: LocalizedError {
    case timedOut
    case failed(Int32)

    var errorDescription: String? {
        switch self {
        case .timedOut: "The installed relay self-test timed out."
        case let .failed(status): "The installed relay exited with status \(status)."
        }
    }
}
