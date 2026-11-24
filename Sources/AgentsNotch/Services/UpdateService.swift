import Foundation
import Observation
import os
import Sparkle

@Observable
@MainActor
final class UpdateService {
    static let packagedOnlyMessage = "Source builds update manually. Rebuild from source or download the latest beta."
    static let manualUpdatesMessage = "This beta updates manually. Download the latest ZIP, quit Agent Notch, and replace the app in Applications."
    var isManualPreview: Bool { bundle.object(forInfoDictionaryKey: "AgentNotchManualUpdates") as? Bool == true }

    private(set) var channelCheckPending = false
    private(set) var state: UpdateState = .idle
    private(set) var lastError: String?

    /// Called just before Sparkle quits the process to swap in the new app.
    var willInstall: (() -> Void)?
    /// Opens Settings → General so a user-initiated check has a visible result.
    var presentStatus: (() -> Void)?

    private var updater: SPUUpdater?
    private var driver: SparkleUpdateDriver?
    private let feedDelegate = UpdateChannelFeedDelegate()
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var started = false
    private let bundle: Bundle
    private static let logger = Logger(subsystem: "com.afonsoferreira.AgentNotch", category: "updates")

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var hostCanUseSparkle: Bool {
        unavailabilityMessage(in: .main) == nil
    }

    /// Ad-hoc packaging opts into manual updates before Sparkle can start or fetch a feed.
    static func unavailabilityMessage(in bundle: Bundle) -> String? {
        guard bundle.bundleIdentifier == "com.afonsoferreira.AgentNotch",
              bundle.bundlePath.hasSuffix(".app") else { return packagedOnlyMessage }
        if bundle.object(forInfoDictionaryKey: "AgentNotchManualUpdates") as? Bool == true {
            return manualUpdatesMessage
        }
        guard bundle.object(forInfoDictionaryKey: "SUFeedURL") is String,
              bundle.object(forInfoDictionaryKey: "SUPublicEDKey") is String,
              FileManager.default.fileExists(
                  atPath: bundle.privateFrameworksPath.map { "\($0)/Sparkle.framework" } ?? ""
              ) else { return packagedOnlyMessage }
        return nil
    }

    func start() {
        guard !started else { return }
        if let message = Self.unavailabilityMessage(in: bundle) {
            started = true
            state = .unavailable(message)
            return
        }

        let driver = SparkleUpdateDriver()
        driver.service = self
        feedDelegate.service = self
        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: driver,
            delegate: feedDelegate
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

    /// Retire the previous Sparkle session before checking the newly selected feed.
    func channelDidChange() {
        start()
        guard updater != nil else { return }
        discardPreviousOffer()
        checkSelectedChannelIfPending()
    }

    func discardPreviousOffer() {
        channelCheckPending = true
        state = .checking
        lastError = nil
        let download = foundReply
        let install = installReply
        foundReply = nil
        installReply = nil
        driver?.cancelCurrentOperation()
        download?(.dismiss)
        // Skipping a prepared installation cancels Sparkle's install-on-quit.
        install?(.skip)
    }

    func checkSelectedChannelIfPending() {
        guard channelCheckPending, let updater, !updater.sessionInProgress else { return }
        channelCheckPending = false
        updater.checkForUpdates()
    }

    func check() {
        presentStatusSurface()
        start()
        guard let updater, !channelCheckPending else { return }
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

    func noteNoUpdate(aheadOfSelectedRelease: Bool = false) {
        apply(.noUpdate)
        if state == .upToDate, aheadOfSelectedRelease, UpdateChannel.current == .stable {
            state = .awaitingStableRelease
        }
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
