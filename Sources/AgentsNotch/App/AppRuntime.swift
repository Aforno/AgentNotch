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
    weak var panelController: NotchPanelController?

    private let persistence = SessionPersistence()
    private var socketServer: UnixSocketServer?
    /// Coalesces rapid session writes so an older snapshot cannot overwrite a newer one.
    private var persistTask: Task<Void, Never>?

    init() {
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
        let saved = await persistence.load()
        let restoredActives = saved.contains(where: \.isActive)
        activity.replaceSessions(saved)
        // Hook adapters cannot verify process liveness. Complete restored actives
        // so a missed Stop/SessionEnd cannot leave sessions active forever; later
        // hook events resume a session if the provider is still running.
        activity.completeUnverifiedActiveSessions()
        reconcileGrokSessionContext()
        #if DEBUG
        // Simulator state is intentionally ephemeral. This also removes rows
        // written by older debug builds before simulator persistence was split.
        simulator.reset()
        #endif
        if persistableSessions.count != saved.count || restoredActives {
            await persistence.save(persistableSessions)
        }
        activity.onSessionsChanged = { [weak self] _ in
            self?.schedulePersist()
        }

        let activity = activity
        let server = UnixSocketServer { event in
            Task { @MainActor in activity.ingest(event) }
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

        for adapter in providerAdapters {
            try? await adapter.startMonitoring()
        }
    }

    func stop() {
        persistTask?.cancel()
        persistTask = nil
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
            await persistence.save(persistableSessions)
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
                workspaceRoot: workspace
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
            guard var event = context.workflowEvent(now: Date(), workingDirectory: nil) else {
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
            activity.ingest(event)
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
