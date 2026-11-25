import Foundation
import Observation
import os
import Sparkle

@Observable
@MainActor
final class UpdateService {
    static let packagedOnlyMessage = "Source builds update manually. Rebuild from source or download the latest beta."
    static let manualUpdatesMessage = "This beta updates manually. Download the latest release, quit Agent Notch, and replace the app in Applications."
    var isManualPreview: Bool { bundle.object(forInfoDictionaryKey: "AgentNotchManualUpdates") as? Bool == true }
    var selectedChannel: UpdateChannel {
        if bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String == UpdateChannel.previewFeedURL {
            return .preview
        }
        return UpdateChannel.selected(in: preferences)
    }

    private(set) var channelCheckPending = false
    private(set) var state: UpdateState = .idle

    /// Opens Settings → General so a user-initiated check has a visible result.
    var presentStatus: (() -> Void)?

    private var updater: SPUUpdater?
    private var driver: SparkleUpdateDriver?
    private let feedDelegate = UpdateChannelFeedDelegate()
    private var foundReply: ((SPUUserUpdateChoice) -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var userRequestedInstall = false
    private var started = false
    private let bundle: Bundle
    private let preferences: UserDefaults
    private static let logger = Logger(subsystem: "com.afonsoferreira.AgentNotch", category: "updates")

    init(bundle: Bundle = .main, preferences: UserDefaults = .standard) {
        self.bundle = bundle
        self.preferences = preferences
    }

    private var automaticallyInstalls: Bool {
        preferences.bool(forKey: AppPreferences.Key.automaticallyCheckForUpdates)
            && preferences.bool(forKey: AppPreferences.Key.automaticallyInstallUpdates)
    }

    var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var hostCanUseSparkle: Bool {
        unavailabilityMessage(in: .main) == nil
    }

    /// Manual builds opt out before Sparkle can start or fetch a feed.
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
        // Keep downloads in the custom driver so channel changes can cancel them.
        updater.automaticallyDownloadsUpdates = false
        updater.sendsSystemProfile = false
        do {
            try updater.start()
            // Only latch after Sparkle accepts the session so Retry can start() again.
            started = true
            updater.automaticallyChecksForUpdates = preferences.bool(
                forKey: AppPreferences.Key.automaticallyCheckForUpdates
            )
            self.driver = driver
            self.updater = updater
            checkInBackgroundIfIdle()
        } catch {
            Self.logger.error("Sparkle failed to start: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        start()
        updater?.automaticallyChecksForUpdates = enabled
        guard enabled else { return }
        installPendingUpdateAutomatically()
        checkInBackgroundIfIdle()
    }

    /// Apply new preferences to an existing offer or check in the background.
    func automaticInstallationPreferenceDidChange() {
        guard automaticallyInstalls else { return }
        installPendingUpdateAutomatically()
        checkInBackgroundIfIdle()
    }

    private func installPendingUpdateAutomatically() {
        guard automaticallyInstalls else { return }
        beginDownload()
        install()
    }

    private func checkInBackgroundIfIdle() {
        if let updater, updater.automaticallyChecksForUpdates, !updater.sessionInProgress {
            updater.checkForUpdatesInBackground()
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
        userRequestedInstall = false
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
        updater.checkForUpdates()
    }

    func presentStatusSurface() {
        presentStatus?()
    }

    /// A single user action authorizes both the download and the relaunch.
    func downloadAndInstall() {
        guard foundReply != nil else { return }
        userRequestedInstall = true
        beginDownload()
    }

    private func beginDownload() {
        guard let reply = foundReply else { return }
        foundReply = nil
        apply(.downloadStarted)
        reply(.install)
    }

    func install() {
        guard let reply = installReply else { return }
        installReply = nil
        userRequestedInstall = false
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
        if automaticallyInstalls { beginDownload() }
    }

    func noteNoUpdate(aheadOfSelectedRelease: Bool = false) {
        apply(.noUpdate)
        if state == .upToDate, aheadOfSelectedRelease, selectedChannel == .stable {
            state = .awaitingStableRelease
        }
    }

    func noteFailure(_ message: String) {
        foundReply = nil
        installReply = nil
        userRequestedInstall = false
        apply(.failed(message))
    }

    func noteDownloadStarted() {
        apply(.downloadStarted)
    }

    func noteDownloadProgress(_ percent: Double) {
        apply(.downloadProgress(percent))
    }

    func noteReadyToInstall(
        version: String? = nil,
        install: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let shouldInstall = userRequestedInstall || automaticallyInstalls
        if let version {
            apply(.updateAvailable(version: version))
        } else if !shouldInstall {
            // Automatic installation was turned off during this download.
            // Sparkle can install a prepared update on quit unless it is canceled.
            install(.skip)
            return
        }
        installReply = install
        apply(.downloadComplete)
        if shouldInstall { self.install() }
    }

    func noteSessionEnded() {
        foundReply = nil
        installReply = nil
        userRequestedInstall = false
        apply(.sessionEnded)
    }

    private func apply(_ event: UpdateEvent) {
        state = reduceUpdateState(state, event)
    }
}
