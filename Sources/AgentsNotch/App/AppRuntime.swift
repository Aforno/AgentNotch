import AgentsNotchCore
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppRuntime {
    let activity: AgentActivityService
    let integrations: [ProviderIntegrationManager]
    let notifications: AgentNotificationService
    let updates: UpdateService
    #if DEBUG
    let simulator: DebugEventSimulator
    #endif

    private(set) var socketStatus = "Starting"
    private(set) var socketError: String?
    private(set) var replySocketError: String?
    private(set) var liveReplyIDs: Set<UUID> = []
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
    private let persistScheduler: SessionPersistScheduler
    private let socketURL: URL
    private let replySocketURL: URL
    private let monitorProviders: Bool
    private let answersFromNotch: @Sendable () -> Bool
    private let answerModeAvailability: AnswerModeAvailability
    private let privacyModeEnabled: @Sendable () -> Bool
    private let grokHome: URL
    private let codexHome: URL
    private let historyRetentionDays: () -> Int?
    private let originActivation = OriginActivationService()
    private var socketServer: UnixSocketServer?
    private var replyServer: UnixReplyServer?
    /// Completes sessions still in `.unknown` when no live hook confirms them.
    private var unknownGraceTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var acceptsEvents = false
    private var isRestoring = false
    private var startupEvents: [AgentEvent] = []

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
        replySocketURL: URL = AgentReplySocketLocation.defaultURL,
        monitorProviders: Bool = true,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok"),
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
        providerHomeDirectoryURL: URL? = nil,
        bundledRelayURL: URL? = nil,
        persistDebounceDuration: Duration = .milliseconds(350),
        persistMaximumDelay: Duration = .seconds(2),
        historyRetentionDays: @escaping () -> Int? = {
            UserDefaults.standard.object(forKey: "historyRetentionDays") as? Int
        },
        answersFromNotch: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "answerFromNotchEnabled")
        },
        privacyModeEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: "privacyModeEnabled")
        }
    ) {
        self.persistence = persistence
        persistScheduler = SessionPersistScheduler(
            persistence: persistence,
            debounceDuration: persistDebounceDuration,
            maximumDelay: persistMaximumDelay
        )
        self.socketURL = socketURL
        self.replySocketURL = replySocketURL
        self.monitorProviders = monitorProviders
        self.answersFromNotch = answersFromNotch
        let answerModeAvailability = AnswerModeAvailability()
        self.answerModeAvailability = answerModeAvailability
        self.privacyModeEnabled = privacyModeEnabled
        self.grokHome = grokHome
        self.codexHome = codexHome
        self.historyRetentionDays = historyRetentionDays
        activity = AgentActivityService()
        let integrations = Self.integratedProviders.map { provider in
            ProviderIntegrationManager(
                provider: provider,
                homeDirectoryURL: providerHomeDirectoryURL,
                bundledRelayURL: bundledRelayURL,
                answersFromNotch: {
                    answersFromNotch() && !privacyModeEnabled() && answerModeAvailability.value
                }
            )
        }
        self.integrations = integrations
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
        if answersFromNotch() {
            _ = startReplySocket()
        }
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
        persistScheduler.setWritesAllowed(false)
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

    @discardableResult
    private func startReplySocket() -> Bool {
        let server = UnixReplyServer(socketURL: replySocketURL) { [weak self] replyIDs in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.liveReplyIDs = replyIDs
                self.activity.reconcilePendingReplies(isLive: replyIDs.contains)
            }
        }
        do {
            try server.start()
            replyServer = server
            answerModeAvailability.value = true
            replySocketError = nil
            return true
        } catch {
            replyServer = nil
            liveReplyIDs = []
            answerModeAvailability.value = false
            replySocketError = "Answer from the notch is unavailable: \(error.localizedDescription)"
            return false
        }
    }

    func applyAnswerFromNotchEnabled(_ enabled: Bool) {
        if enabled {
            if replyServer == nil {
                _ = startReplySocket()
            }
        } else {
            replyServer?.stop()
            replyServer = nil
            liveReplyIDs = []
            answerModeAvailability.value = false
            replySocketError = nil
        }
        refreshProviderHooks()
    }

    func applyPrivacyModeEnabled(_ enabled: Bool) {
        if enabled {
            replyServer?.stop()
            replyServer = nil
            liveReplyIDs = []
            answerModeAvailability.value = false
        } else if answersFromNotch(), replyServer == nil {
            _ = startReplySocket()
        }
        refreshProviderHooks()
    }

    private func refreshProviderHooks() {
        guard monitorProviders else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for integration in integrations {
                await integration.prepareForMonitoring()
            }
        }
    }

    func canAnswer(_ session: AgentSession) -> Bool {
        guard !privacyModeEnabled(),
              session.state == .waitingForUser,
              let pending = session.pendingReply
        else { return false }
        #if DEBUG
        if DebugEventSimulator.isSimulated(session) {
            return true
        }
        #endif
        guard answersFromNotch() else { return false }
        // liveReplyIDs is a cached snapshot for reconciliation. Registration
        // can land on replyServer before that cache updates on the main actor.
        return liveReplyIDs.contains(pending.replyId)
            || replyServer?.isPending(pending.replyId) == true
    }

    func answer(
        _ session: AgentSession,
        decision: AgentReplyDecision,
        optionId: String? = nil,
        answers: [String: [String]]? = nil
    ) {
        guard canAnswer(session), let pending = session.pendingReply else { return }
        let reply = AgentReply(
            replyId: pending.replyId,
            decision: decision,
            optionId: optionId,
            answers: answers
        )
        #if DEBUG
        let simulated = DebugEventSimulator.isSimulated(session)
        #else
        let simulated = false
        #endif
        let delivered = replyServer?.submit(reply) ?? false
        guard delivered || simulated else { return }
        let remaining = session.pendingReplies.filter { candidate in
            candidate.replyId != pending.replyId
                && replyServer?.isPending(candidate.replyId) == true
        }
        let activityText: String = switch decision {
        case .deny:
            "Denied"
        case .allow:
            "Allowed"
        case .option:
            pending.options.first { $0.id == optionId }?.label ?? "Answered"
        case .cancel:
            "Cancelled"
        }
        if let next = remaining.last {
            process(
                AgentEvent(
                    type: .waiting,
                    sessionId: session.id,
                    provider: session.provider,
                    activity: activityText,
                    state: .waitingForUser,
                    pendingReply: next
                ),
                notify: false
            )
        } else {
            process(
                AgentEvent(
                    type: .activity,
                    sessionId: session.id,
                    provider: session.provider,
                    activity: activityText,
                    state: .running
                ),
                notify: false
            )
        }
    }

    private func restorePersistedState(generation: Int) async -> Bool {
        let result = await SessionRestorePipeline.restore(
            generation: generation,
            activity: activity,
            persistence: persistence,
            grokHome: grokHome,
            codexHome: codexHome,
            persistableSessions: { [weak self] in self?.persistableSessions ?? [] },
            historyRetentionDays: historyRetentionDays,
            isCurrentLifecycle: { [weak self] generation in
                self?.isCurrentLifecycle(generation) ?? false
            },
            resetSimulator: { [weak self] in
                #if DEBUG
                // Simulator state is intentionally ephemeral. This also removes
                // rows written by older debug builds.
                self?.simulator.reset()
                #endif
            }
        )
        guard let result else { return false }
        persistScheduler.setWritesAllowed(result.writesAllowed)
        if result.writesAllowed {
            persistenceError = result.persistenceError
            persistenceRecoveryNotice = result.persistenceRecoveryNotice
        } else {
            persistenceError = result.persistenceError
            persistenceRecoveryNotice = nil
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
        for integration in integrations {
            guard isCurrentLifecycle(generation) else { return false }
            await integration.prepareForMonitoring()
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
        persistScheduler.cancelPending()
        if persistScheduler.writesAllowed {
            do {
                try persistScheduler.flushSynchronously(snapshot: persistableSessions)
                persistenceError = nil
            } catch {
                persistenceError = "Could not save session history: \(error.localizedDescription)"
            }
        }
        socketServer?.stop()
        socketServer = nil
        replyServer?.stop()
        replyServer = nil
        liveReplyIDs = []
        answerModeAvailability.value = false
    }

    private func schedulePersist() {
        persistScheduler.schedule(
            snapshot: { [weak self] in self?.persistableSessions ?? [] },
            onResult: { [weak self] error in
                self?.persistenceError = error
            }
        )
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
        let sessionID = event.sessionId
        let previousState = activity.session(id: sessionID)?.state
        guard activity.ingest(event) else { return }
        if event.resolvedState == .completed || event.resolvedState == .failed {
            pruneHistory()
        }
        if event.metadata?["source"] != "self-test" {
            lastEventReceivedAt[event.provider] = Date()
            integration(for: event.provider)?.noteEventReceived()
        }
        guard let session = activity.session(id: sessionID) else { return }

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

    func open(_ session: AgentSession, action: OriginOpenAction) {
        originActivation.open(session, action: action)
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

private final class AnswerModeAvailability: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
