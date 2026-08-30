import AgentsNotchCore
import Foundation
import Observation

enum ProviderIntegrationStatus: Equatable {
    /// Hooks / relay are not present on disk.
    case notInstalled
    /// Hooks are installed; no genuine provider event has been observed yet.
    case awaitingFirstEvent
    /// At least one genuine provider event was received while hooks were installed.
    case connected
    case unavailable(String)

    var title: String {
        switch self {
        case .notInstalled: "Not installed"
        case .awaitingFirstEvent: "Awaiting first event"
        case .connected: "Connected"
        case let .unavailable(message): message
        }
    }

    var canInstall: Bool {
        switch self {
        case .notInstalled, .unavailable: true
        case .awaitingFirstEvent, .connected: false
        }
    }

    var isInstalled: Bool {
        switch self {
        case .awaitingFirstEvent, .connected: true
        case .notInstalled, .unavailable: false
        }
    }

    var isConnected: Bool { self == .connected }
}

@Observable
@MainActor
final class ProviderIntegrationManager {
    nonisolated let provider: AgentProvider
    private(set) var status: ProviderIntegrationStatus = .notInstalled
    private(set) var lastError: String?
    /// Remembers that a real (non-self-test) provider event has been observed.
    /// Survives refresh while hooks remain installed so Connected is not
    /// demoted by a no-op status recompute. Cleared when hooks disappear or
    /// on uninstall so reinstall cannot falsely report Connected.
    private(set) var hasReceivedEvent = false
    private var maintenanceGeneration = 0

    nonisolated private let store: ProviderHookStore
    nonisolated private let answersFromNotch: @Sendable () -> Bool

    init(
        provider: AgentProvider,
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil,
        bundledRelayURL: URL? = nil,
        answersFromNotch: @escaping @Sendable () -> Bool = { false }
    ) {
        self.provider = provider
        self.answersFromNotch = answersFromNotch
        store = ProviderHookStore(
            provider: provider,
            fileSystem: ProviderFileSystem(fileManager),
            homeDirectoryURL: homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser,
            bundledRelayURL: bundledRelayURL
        )
    }

    nonisolated var installedRelayURL: URL { store.installedRelayURL }

    nonisolated var bundledRelayURL: URL? { store.bundledRelayURL }

    /// Provider-specific guidance shown while an observer is installed but not
    /// yet verified by a live event.
    var trustInstructions: String? {
        guard status == .awaitingFirstEvent else { return nil }
        return switch provider {
        case .codex:
            "Open /hooks in Codex once to review and trust the installed lifecycle hooks."
        case .openCode:
            "Restart OpenCode after installing the plugin, then start a new session."
        default:
            nil
        }
    }

    /// Recomputes install health from disk. Pass `hasReceivedEvent: true` when the runtime
    /// already observed a genuine event for this provider (e.g. Settings refresh).
    func refreshStatus(hasReceivedEvent knownEvent: Bool = false) {
        if knownEvent {
            hasReceivedEvent = true
        }
        lastError = nil
        let isInstalled = store.looksInstalled()
        guard isInstalled
        else {
            // Hooks/relay gone (manual removal or uninstall). Drop sticky
            // verification so a later install() cannot report Connected
            // without a post-reinstall event.
            hasReceivedEvent = false
            status = .notInstalled
            return
        }
        status = hasReceivedEvent ? .connected : .awaitingFirstEvent
    }

    /// Promote to Connected after a genuine provider event (not self-test).
    func noteEventReceived() {
        switch status {
        case .awaitingFirstEvent, .connected:
            hasReceivedEvent = true
            status = .connected
        case .notInstalled, .unavailable:
            // Do not sticky-set while uninstalled; reinstall must await a new event.
            break
        }
    }

    func prepareForMonitoring() async {
        maintenanceGeneration &+= 1
        let generation = maintenanceGeneration
        let answering = answersFromNotch()
        let preparation = await Task.detached(priority: .utility) { [store] in
            store.prepareForMonitoringOnDisk(answersFromNotch: answering)
        }.value
        guard generation == maintenanceGeneration else { return }
        if let error = preparation.error {
            lastError = error
            status = .unavailable("Integration update failed")
        } else if preparation.isInstalled {
            lastError = nil
            status = hasReceivedEvent ? .connected : .awaitingFirstEvent
        } else {
            hasReceivedEvent = false
            lastError = nil
            status = .notInstalled
        }
    }

    func install() {
        maintenanceGeneration &+= 1
        do {
            try store.install(answersFromNotch: answersFromNotch())
            status = hasReceivedEvent ? .connected : .awaitingFirstEvent
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Installation failed")
        }
    }

    func uninstall() {
        maintenanceGeneration &+= 1
        do {
            try store.uninstall()
            hasReceivedEvent = false
            status = .notInstalled
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            status = .unavailable("Removal failed")
        }
    }
}
