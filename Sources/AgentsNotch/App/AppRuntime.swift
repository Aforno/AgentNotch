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
    private var settingsWindowController: SettingsWindowController?
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
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(runtime: self)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
