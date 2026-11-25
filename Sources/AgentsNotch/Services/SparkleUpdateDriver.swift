import Foundation
import Sparkle

/// Suppresses Sparkle windows while `UpdateService` owns the update UI state.
@MainActor
final class SparkleUpdateDriver: NSObject, SPUUserDriver {
    weak var service: UpdateService?

    private var activeService: UpdateService? {
        service?.channelCheckPending == true ? nil : service
    }

    private var cancellation: (() -> Void)?

    func cancelCurrentOperation() {
        let cancel = cancellation
        cancellation = nil
        cancel?()
    }

    private var expectedContentLength: UInt64 = 0
    private var receivedContentLength: UInt64 = 0

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        _ = request
        let enabled = UserDefaults.standard.bool(
            forKey: AppPreferences.Key.automaticallyCheckForUpdates
        )
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: enabled, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        activeService?.noteUserInitiatedCheck()
        self.cancellation = cancellation
        if activeService == nil { cancelCurrentOperation() }
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        cancellation = nil
        // Sparkle can resume a staged archive before it consults the selected feed.
        if let service, let archive = appcastItem.fileURL,
           let channel = UpdateChannel.archiveChannel(for: archive), channel != service.selectedChannel {
            service.discardPreviousOffer()
        }
        guard let activeService else {
            reply(state.stage == .notDownloaded ? .dismiss : .skip)
            return
        }
        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
            activeService.noteFailure("This update cannot be installed from inside Agent Notch.")
            return
        }

        let version = appcastItem.displayVersionString
        switch state.stage {
        // A cached download still needs to be extracted before it can be installed.
        case .notDownloaded, .downloaded:
            activeService.noteUpdateAvailable(version: version, download: reply)
        case .installing:
            activeService.noteReadyToInstall(version: version, install: reply)
        @unknown default:
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        switch sparkleNoUpdateOutcome(error) {
        case .currentVersion:
            activeService?.noteNoUpdate()
        case .newerThanLatest:
            activeService?.noteNoUpdate(aheadOfSelectedRelease: true)
        case let .unavailable(message):
            activeService?.noteFailure(message)
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        activeService?.noteFailure(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedContentLength = 0
        receivedContentLength = 0
        activeService?.noteDownloadStarted()
        self.cancellation = cancellation
        if activeService == nil { cancelCurrentOperation() }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.expectedContentLength = expectedContentLength
        reportDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedContentLength += length
        reportDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        activeService?.noteDownloadProgress(1)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        activeService?.noteDownloadProgress(1)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        guard let activeService else {
            reply(.skip)
            return
        }
        activeService.noteReadyToInstall(install: reply)
    }

    // The install reply already drives the progress UI. The app accepts Sparkle's quit request.
    func showInstallingUpdate(
        withApplicationTerminated _: Bool,
        retryTerminatingApplication _: @escaping () -> Void
    ) {}

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        cancellation = nil
        expectedContentLength = 0
        receivedContentLength = 0
        activeService?.noteSessionEnded()
    }

    func showUpdateInFocus() {
        activeService?.presentStatusSurface()
    }

    private func reportDownloadProgress() {
        guard expectedContentLength > 0 else { return }
        let percent = Double(receivedContentLength) / Double(expectedContentLength)
        activeService?.noteDownloadProgress(percent)
    }
}

enum SparkleNoUpdateOutcome: Equatable {
    case newerThanLatest
    case currentVersion
    case unavailable(String)
}

/// Sparkle's "no update" callback is not "you are on the latest version".
/// An update may exist and still be ineligible (older macOS, Intel Mac, etc.).
func sparkleNoUpdateOutcome(_ error: Error) -> SparkleNoUpdateOutcome {
    let nsError = error as NSError
    if let reason = sparkleNoUpdateReason(from: nsError) {
        switch reason {
        case .onNewerThanLatestVersion:
            return .newerThanLatest
        case .onLatestVersion:
            return .currentVersion
        case .unknown, .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64:
            return .unavailable(sparklePresentedMessage(nsError))
        @unknown default:
            return .unavailable(sparklePresentedMessage(nsError))
        }
    }
    return .unavailable(sparklePresentedMessage(nsError))
}

private func sparkleNoUpdateReason(from error: NSError) -> SPUNoUpdateFoundReason? {
    let value = error.userInfo[SPUNoUpdateFoundReasonKey]
    if let reason = value as? SPUNoUpdateFoundReason {
        return reason
    }
    if let number = value as? NSNumber {
        return SPUNoUpdateFoundReason(rawValue: number.int32Value)
    }
    return nil
}

private func sparklePresentedMessage(_ error: NSError) -> String {
    let suggestion = error.localizedRecoverySuggestion?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let suggestion, !suggestion.isEmpty {
        return suggestion
    }
    let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    return description.isEmpty ? "A new update is not available." : description
}
