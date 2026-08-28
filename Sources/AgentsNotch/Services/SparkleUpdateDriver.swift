import Foundation
import Sparkle

/// Sparkle user driver that never presents Sparkle windows. Status lives in
/// `UpdateService` so Settings can check, download, then restart like T3 Code.
@MainActor
final class SparkleUpdateDriver: NSObject, SPUUserDriver {
    weak var service: UpdateService?

    private var expectedContentLength: UInt64 = 0
    private var receivedContentLength: UInt64 = 0

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        _ = request
        let enabled = UserDefaults.standard.bool(forKey: UpdateService.automaticChecksDefaultsKey)
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: enabled, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        service?.noteUserInitiatedCheck()
        _ = cancellation
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        if appcastItem.isInformationOnlyUpdate {
            reply(.dismiss)
            service?.noteCheckFailed("This update cannot be installed from inside Agent Notch.")
            return
        }

        let version = appcastItem.displayVersionString
        switch state.stage {
        case .notDownloaded:
            service?.noteUpdateAvailable(version: version, download: reply)
        case .downloaded:
            service?.noteDownloaded(version: version, install: reply)
        case .installing:
            service?.noteInstalling(install: reply)
        @unknown default:
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        service?.noteNoUpdate()
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        service?.noteUpdaterError(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedContentLength = 0
        receivedContentLength = 0
        service?.noteDownloadStarted()
        _ = cancellation
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
        service?.noteDownloadProgress(1)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        service?.noteDownloadProgress(1)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        service?.noteReadyToInstall(install: reply)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        service?.noteInstalling()
        _ = applicationTerminated
        _ = retryTerminatingApplication
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        expectedContentLength = 0
        receivedContentLength = 0
        service?.noteSessionEnded()
    }

    func showUpdateInFocus() {}

    private func reportDownloadProgress() {
        guard expectedContentLength > 0 else { return }
        let percent = Double(receivedContentLength) / Double(expectedContentLength)
        service?.noteDownloadProgress(percent)
    }
}
