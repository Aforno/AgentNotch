import AgentsNotchCore
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppRuntime {
    let activity: AgentActivityService
    let codexIntegration: ProviderIntegrationManager
    let claudeIntegration: ProviderIntegrationManager
    let grokIntegration: ProviderIntegrationManager
    let providerAdapters: [HookProviderAdapter]
    #if DEBUG
    let simulator: DebugEventSimulator
    #endif

    private(set) var socketStatus = "Starting"
    private(set) var socketError: String?
    private(set) var persistenceError: String?
    weak var panelController: NotchPanelController?

    private let persistence: SessionPersistence
    private let socketURL: URL
    private let monitorProviders: Bool
    private let grokHome: URL
    private var socketServer: UnixSocketServer?
    /// Coalesces rapid session writes so an older snapshot cannot overwrite a newer one.
    private var persistTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var acceptsEvents = false
    private var isRestoring = false
    private var startupEvents: [AgentEvent] = []

    init(
        persistence: SessionPersistence = SessionPersistence(),
        socketURL: URL = AgentSocketLocation.defaultURL,
        monitorProviders: Bool = true,
        grokHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok")
    ) {
        self.persistence = persistence
        self.socketURL = socketURL
        self.monitorProviders = monitorProviders
        self.grokHome = grokHome
        activity = AgentActivityService()
        codexIntegration = ProviderIntegrationManager(provider: .codex)
        claudeIntegration = ProviderIntegrationManager(provider: .claudeCode)
        grokIntegration = ProviderIntegrationManager(provider: .grok)
        providerAdapters = [codexIntegration, claudeIntegration, grokIntegration]
            .map(HookProviderAdapter.init)
        #if DEBUG
        simulator = DebugEventSimulator(activity: activity)
        #endif
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
        // Hook adapters cannot verify process liveness. Complete restored running
        // sessions so a missed Stop/SessionEnd cannot leave rows active forever.
        // Waiting rows are preserved because the user may still owe input.
        activity.completeUnverifiedActiveSessions()
        reconcileGrokSessionContext()
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
            activity.ingest(event)
        }

        if monitorProviders {
            for adapter in providerAdapters {
                guard acceptsEvents, generation == lifecycleGeneration else { return }
                try? await adapter.startMonitoring()
            }
        }
    }

    func stop() {
        lifecycleGeneration += 1
        acceptsEvents = false
        isRestoring = false
        startupEvents.removeAll()
        activity.onSessionsChanged = nil
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
            activity.ingest(event)
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
            // completeUnverifiedActiveSessions() just marked restored actives
            // completed. Leftover on-disk workflow status (e.g. active/running)
            // must not reopen those sessions as phantoms across relaunch.
            if let session = activity.sessions.first(where: { $0.id == event.sessionId }),
               !session.isActive,
               event.resolvedState.isActive
            {
                event.state = session.state
                event.type = session.state == .failed ? .failed : .completed
            }
            activity.reconcileRestoredWorkflow(event)
        }
    }

    private var persistableSessions: [AgentSession] {
        #if DEBUG
        activity.sessions.filter { !DebugEventSimulator.isSimulated($0) }
        #else
        activity.sessions
        #endif
    }

    func open(_ session: AgentSession) {
        if let applicationURL = session.applicationURL {
            NSWorkspace.shared.open(applicationURL)
        } else if let directory = session.workingDirectory {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory)])
        }
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        guard let item = settingsMenuItem(in: NSApp.mainMenu),
              let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }

        for item in menu.items {
            if item.keyEquivalent == ",",
               item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let match = settingsMenuItem(in: item.submenu) {
                return match
            }
        }
        return nil
    }
}
