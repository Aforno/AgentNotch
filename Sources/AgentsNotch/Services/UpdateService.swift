import Foundation
import Observation
import os
import Sparkle

@Observable
@MainActor
final class UpdateService {
    static let packagedOnlyMessage = "Automatic updates are only available in packaged production builds."

    private(set) var state: UpdateState = .idle
    private(set) var lastError: String?

    /// Called just before Sparkle quits the process to swap in the new app.
    var willInstall: (() -> Void)?
    /// Opens Settings → General so a user-initiated check has a visible result.
    var presentStatus: (() -> Void)?

    private var updater: SPUUpdater?
    private var driver: SparkleUpdateDriver?
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var started = false
    private static let logger = Logger(subsystem: "com.afonsoferreira.AgentNotch", category: "updates")

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var hostCanUseSparkle: Bool {
        let bundle = Bundle.main
        guard bundle.bundleIdentifier == "com.afonsoferreira.AgentNotch" else { return false }
        guard bundle.bundlePath.hasSuffix(".app") else { return false }
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") is String else { return false }
        guard bundle.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return false }
        return FileManager.default.fileExists(
            atPath: bundle.privateFrameworksPath.map { "\($0)/Sparkle.framework" } ?? ""
        )
    }

    func start() {
        guard !started else { return }
        guard Self.hostCanUseSparkle else {
            started = true
            state = .unavailable(Self.packagedOnlyMessage)
            return
        }

        let driver = SparkleUpdateDriver()
        driver.service = self
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: driver,
            delegate: nil
        )
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        do {
            try updater.start()
            // Only latch after Sparkle accepts the session so Retry can start() again.
            started = true
            updater.automaticallyChecksForUpdates = UserDefaults.standard.bool(
                forKey: AppPreferences.Key.automaticallyCheckForUpdates
            )
            self.driver = driver
            self.updater = updater
            if updater.automaticallyChecksForUpdates {
                updater.checkForUpdatesInBackground()
            }
        } catch {
            Self.logger.error("Sparkle failed to start: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        start()
        updater?.automaticallyChecksForUpdates = enabled
        if enabled {
            updater?.checkForUpdatesInBackground()
        }
    }

    func check() {
        presentStatusSurface()
        start()
        guard let updater else { return }
        lastError = nil
        updater.checkForUpdates()
    }

    func presentStatusSurface() {
        presentStatus?()
    }

    func download() {
        lastError = nil
        guard let reply = foundReply else { return }
        foundReply = nil
        apply(.downloadStarted)
        reply(.install)
    }

    func install() {
        lastError = nil
        guard let reply = installReply else { return }
        installReply = nil
        willInstall?()
        apply(.installStarted)
        reply(.install)
    }

    func noteUserInitiatedCheck() {
        apply(.checkStarted)
    }

    func noteUpdateAvailable(
        version: String,
        download: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        foundReply = download
        apply(.updateAvailable(version: version))
    }

    func noteDownloaded(
        version: String,
        install: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        installReply = install
        apply(.updateAvailable(version: version))
        apply(.downloadComplete)
    }

    func noteNoUpdate() {
        apply(.noUpdate)
    }

    func noteCheckFailed(_ message: String) {
        lastError = message
        apply(.checkFailed(message))
    }

    func noteUpdaterError(_ message: String) {
        lastError = message
        switch state {
        case .downloading:
            apply(.downloadFailed(message))
        case .installing, .downloaded:
            apply(.installFailed(message))
        default:
            apply(.checkFailed(message))
        }
    }

    func noteDownloadStarted() {
        apply(.downloadStarted)
    }

    func noteDownloadProgress(_ percent: Double) {
        apply(.downloadProgress(percent))
    }

    func noteReadyToInstall(install: @escaping (SPUUserUpdateChoice) -> Void) {
        installReply = install
        apply(.downloadComplete)
    }

    func noteInstalling(install: ((SPUUserUpdateChoice) -> Void)? = nil) {
        if let install {
            willInstall?()
            install(.install)
        }
        apply(.installStarted)
    }

    func noteSessionEnded() {
        switch state {
        case .available, .downloaded, .installing:
            return
        default:
            foundReply = nil
            installReply = nil
            apply(.sessionEnded)
        }
    }

    private func apply(_ event: UpdateEvent) {
        state = reduceUpdateState(state, event)
    }
}
