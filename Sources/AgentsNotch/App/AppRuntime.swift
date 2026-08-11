import AgentsNotchCore
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppRuntime {
    let activity: AgentActivityService
    let integrations: [ProviderIntegrationManager]
    let providerAdapters: [HookProviderAdapter]
    let notifications: AgentNotificationService
    let updates: UpdateService
    #if DEBUG
    let simulator: DebugEventSimulator
    #endif

    private(set) var socketStatus = "Starting"
    private(set) var socketError: String?
    private(set) var persistenceError: String?
    private(set) var persistenceRecoveryNotice: String?
    private(set) var lastEventReceivedAt: [AgentProvider: Date] = [:]
    private(set) var requestedSessionID: String?
    private(set) var activitySearchRequest: UInt64 = 0
    var openActivityCenterHandler: (() -> Void)?
    var openOnboardingHandler: (() -> Void)?
    var openSettingsHandler: (() -> Void)?
    var updateGlobalShortcutHandler: ((String) -> Void)?
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
    /// Bounds persistence latency during a continuous stream of hook events.
    private var persistDeadlineTask: Task<Void, Never>?
    /// Completes sessions still in `.unknown` when no live hook confirms them.
    private var unknownGraceTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var acceptsEvents = false
    private var isRestoring = false
    /// Protects an unreadable history file when it could not be quarantined.
    private var persistenceWritesAllowed = false
    private var startupEvents: [AgentEvent] = []
    private let persistDebounceDuration: Duration
    private let persistMaximumDelay: Duration

    /// How long restored unverified runners stay in `.unknown` before the app
    /// assumes they ended without a hook. Live events cancel this per session.
    static let unknownSessionGracePeriod: Duration = .seconds(90)
    private static let integratedProviders: [AgentProvider] = [
        .codex,
        .claudeCode,
        .grok,
        .geminiCLI,
        .openCode,
        .cursor,
    ]

    init(
        persistence: SessionPersistence = SessionPersistence(),
        socketURL: URL = AgentSocketLocation.defaultURL,
        monitorProviders: Bool = true,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok"),
        providerHomeDirectoryURL: URL? = nil,
        bundledRelayURL: URL? = nil,
        persistDebounceDuration: Duration = .milliseconds(350),
        persistMaximumDelay: Duration = .seconds(2),
        historyRetentionDays: @escaping () -> Int? = {
            UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int
        }
    ) {
        self.persistence = persistence
        self.socketURL = socketURL
        self.monitorProviders = monitorProviders
        self.grokHome = grokHome
        self.persistDebounceDuration = persistDebounceDuration
        self.persistMaximumDelay = persistMaximumDelay
        self.historyRetentionDays = historyRetentionDays
        activity = AgentActivityService()
        let integrations = Self.integratedProviders.map { provider in
            ProviderIntegrationManager(
                provider: provider,
                homeDirectoryURL: providerHomeDirectoryURL,
                bundledRelayURL: bundledRelayURL
            )
        }
        self.integrations = integrations
        providerAdapters = integrations.map(HookProviderAdapter.init)
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
        guard let generation = beginStartup() else { return }
        startSocket(generation: generation)
        guard await restorePersistedState(generation: generation) else { return }
        completeRestoration(generation: generation)
        guard await startProviderMonitoring(generation: generation) else { return }
        updates.checkAutomaticallyIfNeeded()
    }

    private func beginStartup() -> Int? {
        guard !acceptsEvents else { return nil }
        lifecycleGeneration += 1
        acceptsEvents = true
        isRestoring = true
        // Loading decides whether replacing the current history is safe. Keep
        // writes disabled while restoration is still in flight.
        persistenceWritesAllowed = false
        startupEvents.removeAll(keepingCapacity: true)
        return lifecycleGeneration
    }

    private func startSocket(generation: Int) {
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
    }

    private func restorePersistedState(generation: Int) async -> Bool {
        let loadResult = await persistence.load()
        guard isCurrentLifecycle(generation) else { return false }
        persistenceWritesAllowed = loadResult.canSafelyWrite
        if loadResult.canSafelyWrite {
            persistenceError = nil
            persistenceRecoveryNotice = loadResult.recoveryMessage
        } else {
            persistenceError = loadResult.recoveryMessage
            persistenceRecoveryNotice = nil
        }
        activity.replaceSessions(loadResult.sessions)
        // Do not invent completion for restored runners. Dead origin PIDs are
        // completed; everything else becomes `.unknown` until a live hook or
        // the reconnect grace period resolves them. Waiting rows stay waiting.
        activity.reconcileUnverifiedActiveSessions()
        let restoredSessions = activity.sessions
        let grokHome = self.grokHome
        let grokEvidence = await Task.detached(priority: .utility) {
            GrokSessionRestorer.discover(in: restoredSessions, grokHome: grokHome)
        }.value
        guard isCurrentLifecycle(generation) else { return false }
        applyGrokSessionContext(grokEvidence)
        pruneHistory()
        #if DEBUG
        // Simulator state is intentionally ephemeral. This also removes rows
        // written by older debug builds before simulator persistence was split.
        simulator.reset()
        #endif
        if persistenceWritesAllowed {
            // Persist restored Grok relationships and recreate a clean file after
            // successful corruption quarantine. Failed quarantine stays read-only.
            let saveError = await persistence.save(persistableSessions)
            guard isCurrentLifecycle(generation) else { return false }
            if let error = saveError {
                persistenceError = error
            }
        }
        return true
    }

    private func completeRestoration(generation: Int) {
        guard isCurrentLifecycle(generation) else { return }
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
    }

    private func startProviderMonitoring(generation: Int) async -> Bool {
        guard monitorProviders else { return isCurrentLifecycle(generation) }
        for adapter in providerAdapters {
            guard isCurrentLifecycle(generation) else { return false }
            try? await adapter.startMonitoring()
        }
        return isCurrentLifecycle(generation)
    }

    private func isCurrentLifecycle(_ generation: Int) -> Bool {
        acceptsEvents && generation == lifecycleGeneration
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
        persistDeadlineTask?.cancel()
        persistDeadlineTask = nil
        if persistenceWritesAllowed {
            do {
                try persistence.saveSynchronously(persistableSessions)
                persistenceError = nil
            } catch {
                persistenceError = "Could not save session history: \(error.localizedDescription)"
            }
        }
        socketServer?.stop()
        socketServer = nil
    }

    private func schedulePersist() {
        guard persistenceWritesAllowed else { return }
        if persistDeadlineTask == nil {
            persistDeadlineTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: persistMaximumDelay)
                } catch {
                    return
                }
                await flushScheduledPersistence()
            }
        }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: persistDebounceDuration)
            } catch {
                return
            }
            await flushScheduledPersistence()
        }
    }

    private func flushScheduledPersistence() async {
        persistTask?.cancel()
        persistTask = nil
        persistDeadlineTask?.cancel()
        persistDeadlineTask = nil
        guard persistenceWritesAllowed else { return }
        let snapshot = persistableSessions
        persistenceError = await persistence.save(snapshot)
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
        guard activity.ingest(event) else { return }
        if event.resolvedState == .completed || event.resolvedState == .failed {
            pruneHistory()
        }
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

    private func applyGrokSessionContext(_ evidence: GrokRestoreEvidence) {
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
        guard activity.session(id: sessionID) != nil else { return }
        requestedSessionID = sessionID
        let isInNotchSnapshot = activity.notchSnapshot.relatedSessions.contains { $0.id == sessionID }
        if panelController?.isSurfaceEnabled == true, isInNotchSnapshot {
            panelController?.show()
        } else {
            openActivityCenter()
        }
    }

    func consumeRequestedSession(_ sessionID: String) {
        guard requestedSessionID == sessionID else { return }
        requestedSessionID = nil
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

    func focusActivitySearch() {
        openActivityCenter()
        activitySearchRequest &+= 1
    }

    func openOnboarding() {
        openOnboardingHandler?()
    }

    func openSettings() {
        openSettingsHandler?()
    }

    func updateGlobalShortcut(_ rawValue: String) {
        updateGlobalShortcutHandler?(rawValue)
    }

    private func pruneHistory() {
        guard let configuredDays = historyRetentionDays(), configuredDays > 0 else { return }
        let days = max(1, configuredDays)
        activity.pruneCompleted(olderThan: TimeInterval(days * 24 * 60 * 60))
    }

    func integration(for provider: AgentProvider) -> ProviderIntegrationManager? {
        integrations.first { $0.provider == provider }
    }
}
