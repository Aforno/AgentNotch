import AgentsNotchCore
import Foundation

struct MonitoringPreparation: Sendable {
    let isInstalled: Bool
    let error: String?
}

final class ProviderFileSystem: @unchecked Sendable {
    let manager: FileManager

    init(_ manager: FileManager) {
        self.manager = manager
    }
}

/// Shared relay path plus the per-config-shape install strategy.
struct ProviderHookStore: Sendable {
    let provider: AgentProvider
    let fileSystem: ProviderFileSystem
    let homeDirectoryURL: URL
    private let bundledRelayURLOverride: URL?
    private let queue: ProviderInstallQueue
    private let strategy: any HookInstallStrategy

    init(
        provider: AgentProvider,
        fileSystem: ProviderFileSystem,
        homeDirectoryURL: URL,
        bundledRelayURL: URL?,
        queue: ProviderInstallQueue = .shared
    ) {
        self.provider = provider
        self.fileSystem = fileSystem
        self.homeDirectoryURL = homeDirectoryURL
        bundledRelayURLOverride = bundledRelayURL
        self.queue = queue
        if let profile = IntegratedHookProvider(provider: provider) {
            strategy = profile.makeStrategy(homeDirectoryURL: homeDirectoryURL)
        } else {
            strategy = GroupedHooksInstall(
                hooksURL: homeDirectoryURL
                    .appendingPathComponent(".agentsnotch/integrations", isDirectory: true)
                    .appendingPathComponent("\(provider.rawValue).json"),
                eventNames: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SessionEnd"],
                timeoutForEvent: { _ in .seconds(5) }
            )
        }
    }

    var installedRelayURL: URL {
        homeDirectoryURL
            .appendingPathComponent(".agentsnotch/bin", isDirectory: true)
            .appendingPathComponent("agentsnotch-hook")
    }

    var bundledRelayURL: URL? {
        if let bundledRelayURLOverride {
            return bundledRelayURLOverride
        }
        return Bundle.main.resourceURL?
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("agentsnotch-hook")
    }

    func prepareForMonitoringOnDisk(answersFromNotch: Bool) -> MonitoringPreparation {
        queue.sync {
            let io = HookConfigurationIO(fileSystem: fileSystem)
            let relay = hookRelay(answersFromNotch: answersFromNotch)
            guard fileSystem.manager.isExecutableFile(atPath: installedRelayURL.path),
                  strategy.looksInstalled(io: io, relay: relay)
            else {
                return MonitoringPreparation(isInstalled: false, error: nil)
            }
            do {
                try updateInstalledRelayIfNeeded()
                try strategy.updateIfNeeded(io: io, relay: relay)
                return MonitoringPreparation(isInstalled: true, error: nil)
            } catch {
                return MonitoringPreparation(isInstalled: true, error: error.localizedDescription)
            }
        }
    }

    func install(answersFromNotch: Bool) throws {
        try queue.sync {
            try writeBundledRelay()
            try strategy.install(
                io: HookConfigurationIO(fileSystem: fileSystem),
                relay: hookRelay(answersFromNotch: answersFromNotch)
            )
        }
    }

    func uninstall() throws {
        try queue.sync {
            try strategy.uninstall(
                io: HookConfigurationIO(fileSystem: fileSystem),
                relay: hookRelay(answersFromNotch: false)
            )
        }
    }

    func looksInstalled() -> Bool {
        queue.sync {
            let io = HookConfigurationIO(fileSystem: fileSystem)
            let relay = hookRelay(answersFromNotch: false)
            let answeringRelay = hookRelay(answersFromNotch: true)
            return fileSystem.manager.isExecutableFile(atPath: installedRelayURL.path)
                && (strategy.looksInstalled(io: io, relay: relay)
                    || strategy.looksInstalled(io: io, relay: answeringRelay))
        }
    }

    private func hookRelay(answersFromNotch: Bool) -> HookRelayIdentity {
        HookRelayIdentity(
            provider: provider,
            relayURL: installedRelayURL,
            answersFromNotch: answersFromNotch
        )
    }

    private func updateInstalledRelayIfNeeded() throws {
        guard let bundledRelayURL,
              fileSystem.manager.isExecutableFile(atPath: bundledRelayURL.path)
        else { throw ProviderIntegrationError.relayMissing }

        let bundledData = try Data(contentsOf: bundledRelayURL)
        let installedData = try Data(contentsOf: installedRelayURL)
        guard bundledData != installedData else { return }
        try writeBundledRelay(data: bundledData)
    }

    private func writeBundledRelay(data: Data? = nil) throws {
        guard let bundledRelayURL,
              fileSystem.manager.isExecutableFile(atPath: bundledRelayURL.path)
        else { throw ProviderIntegrationError.relayMissing }

        try fileSystem.manager.createDirectory(
            at: installedRelayURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileSystem.manager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: installedRelayURL.deletingLastPathComponent().path
        )
        let relayData = try data ?? Data(contentsOf: bundledRelayURL)
        try relayData.write(to: installedRelayURL, options: .atomic)
        try fileSystem.manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedRelayURL.path)
    }
}

enum ProviderIntegrationError: LocalizedError {
    case relayMissing
    case invalidHooksFile(String)
    case invalidHooksSection(String)
    case invalidHookEvent(String, String)
    case configurationChanged(String)
    case existingOpenCodePlugin(String)
    case incompleteInstallation

    var errorDescription: String? {
        switch self {
        case .relayMissing:
            "The bundled agent relay could not be found. Launch the packaged Agents Notch app."
        case let .invalidHooksFile(path):
            "The existing \(path) file is not a JSON object."
        case let .invalidHooksSection(path):
            "The existing hooks value in \(path) is not a JSON object."
        case let .invalidHookEvent(event, path):
            "The existing \(event) hooks in \(path) are not an array."
        case let .configurationChanged(path):
            "\(path) changed while Agents Notch was updating it. Try again."
        case let .existingOpenCodePlugin(path):
            "Agents Notch will not replace the existing OpenCode plugin at \(path)."
        case .incompleteInstallation:
            "One or more required lifecycle hooks could not be installed."
        }
    }
}
