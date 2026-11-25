@testable import AgentsNotch
import Sparkle
import XCTest

final class UpdateStateMachineTests: XCTestCase {
    func testCheckDoesNotClearDownloadedUpdate() {
        var state = UpdateState.downloaded(version: "0.3.0")
        state = reduceUpdateState(state, .checkStarted)
        XCTAssertEqual(state, .downloaded(version: "0.3.0"))
        state = reduceUpdateState(state, .noUpdate)
        XCTAssertEqual(state, .downloaded(version: "0.3.0"))
    }

    func testProgressIsClamped() {
        var state = UpdateState.downloading(version: "0.3.0", percent: 0)
        state = reduceUpdateState(state, .downloadProgress(1.4))
        XCTAssertEqual(state, .downloading(version: "0.3.0", percent: 1))
        state = reduceUpdateState(state, .downloadProgress(-2))
        XCTAssertEqual(state, .downloading(version: "0.3.0", percent: 0))
    }

    func testUnavailableStateIgnoresCheckEvents() {
        let unavailable = UpdateState.unavailable("packaged only")
        XCTAssertEqual(reduceUpdateState(unavailable, .checkStarted), unavailable)
        XCTAssertEqual(reduceUpdateState(unavailable, .noUpdate), unavailable)
        XCTAssertEqual(
            reduceUpdateState(unavailable, .updateAvailable(version: "0.3.0")),
            unavailable
        )
    }
}

final class UpdateServiceTests: XCTestCase {
    @MainActor
    func testSingleInstallActionDownloadsThenRelaunchesWhenReady() throws {
        let service = UpdateService(preferences: try makePreferences())
        var downloads: [SPUUserUpdateChoice] = []
        var installs: [SPUUserUpdateChoice] = []

        service.noteUpdateAvailable(version: "0.3.0") { downloads.append($0) }
        XCTAssertEqual(service.state, .available(version: "0.3.0"))
        XCTAssertTrue(downloads.isEmpty)
        service.downloadAndInstall()
        service.downloadAndInstall()
        XCTAssertEqual(downloads, [.install])
        XCTAssertEqual(service.state, .downloading(version: "0.3.0", percent: 0))

        service.noteDownloadProgress(0.42)
        XCTAssertEqual(service.state, .downloading(version: "0.3.0", percent: 0.42))
        XCTAssertTrue(installs.isEmpty)
        service.noteReadyToInstall { installs.append($0) }
        service.install()
        XCTAssertEqual(installs, [.install])
        XCTAssertEqual(service.state, .installing(version: "0.3.0"))
    }

    @MainActor
    func testAutomaticInstallRequiresOptInThroughRelaunch() throws {
        let preferences = try makePreferences()
        let service = UpdateService(preferences: preferences)
        var downloads: [SPUUserUpdateChoice] = []
        var installs: [SPUUserUpdateChoice] = []

        preferences.set(true, forKey: AppPreferences.Key.automaticallyInstallUpdates)
        service.noteUpdateAvailable(version: "0.3.0") { downloads.append($0) }
        XCTAssertTrue(downloads.isEmpty)

        preferences.set(true, forKey: AppPreferences.Key.automaticallyCheckForUpdates)
        service.automaticInstallationPreferenceDidChange()
        XCTAssertEqual(downloads, [.install])

        preferences.set(false, forKey: AppPreferences.Key.automaticallyInstallUpdates)
        service.noteReadyToInstall { installs.append($0) }
        XCTAssertEqual(installs, [.skip])
        service.noteSessionEnded()

        preferences.set(true, forKey: AppPreferences.Key.automaticallyInstallUpdates)
        service.noteUpdateAvailable(version: "0.4.0") { downloads.append($0) }
        service.noteReadyToInstall { installs.append($0) }
        XCTAssertEqual(downloads, [.install, .install])
        XCTAssertEqual(installs, [.skip, .install])
        XCTAssertEqual(service.state, .installing(version: "0.4.0"))
    }

    @MainActor
    func testFailedDownloadClearsConsentAndLeavesRetryState() throws {
        let service = UpdateService(preferences: try makePreferences())
        service.noteUpdateAvailable(version: "1.0") { _ in }
        service.downloadAndInstall()
        service.noteFailure("Download interrupted")
        service.noteSessionEnded()
        XCTAssertEqual(service.state, .failed("Download interrupted"))

        var installs: [SPUUserUpdateChoice] = []
        service.noteReadyToInstall(version: "1.0") { installs.append($0) }
        XCTAssertEqual(service.state, .downloaded(version: "1.0"))
        XCTAssertTrue(installs.isEmpty)
    }

    @MainActor
    func testSwitchDiscardsPreparedInstallationAndIgnoresLateCallbacks() throws {
        let service = UpdateService(preferences: try makePreferences())
        let driver = SparkleUpdateDriver()
        driver.service = service
        var choices: [SPUUserUpdateChoice] = []
        service.noteReadyToInstall(version: "1.0") { choices.append($0) }

        service.discardPreviousOffer()
        service.install()
        driver.showUpdaterError(NSError(domain: "old feed", code: 1)) {}
        driver.dismissUpdateInstallation()
        XCTAssertEqual(choices, [.skip])
        XCTAssertEqual(service.state, .checking)

        driver.showReady(toInstallAndRelaunch: { choices.append($0) })
        XCTAssertEqual(choices, [.skip, .skip])
    }

    @MainActor
    func testAdHocPackageNeverStartsSparkle() throws {
        let bundle = try makePackagedBundle(manualUpdates: true)
        let service = UpdateService(bundle: bundle)
        service.start()
        service.setAutomaticChecksEnabled(true)
        service.channelDidChange()
        service.check()
        XCTAssertEqual(service.state, .unavailable(UpdateService.manualUpdatesMessage))
    }

    @MainActor
    func testPackageWithAutomaticUpdatesRemainsEligibleForSparkle() throws {
        let bundle = try makePackagedBundle(manualUpdates: false)
        XCTAssertNil(UpdateService.unavailabilityMessage(in: bundle))
    }

    @MainActor
    func testSourceBuildCannotStartOrInstallUpdates() {
        let service = UpdateService()
        service.start()
        service.setAutomaticChecksEnabled(true)
        service.downloadAndInstall()
        service.install()
        XCTAssertEqual(service.state, .unavailable(UpdateService.packagedOnlyMessage))
    }

    @MainActor
    func testDriverAcknowledgesCurrentVersions() {
        for reason in [SPUNoUpdateFoundReason.onLatestVersion, .onNewerThanLatestVersion] {
            let service = UpdateService()
            let driver = SparkleUpdateDriver()
            driver.service = service
            var acknowledged = false
            driver.showUpdateNotFoundWithError(sparkleNoUpdateError(reason: reason)) {
                acknowledged = true
            }
            XCTAssertTrue(acknowledged, "\(reason)")
            let waitingForStable = reason == .onNewerThanLatestVersion && UpdateChannel.current == .stable
            XCTAssertEqual(service.state, waitingForStable ? .awaitingStableRelease : .upToDate, "\(reason)")
        }
    }

    @MainActor
    func testDriverReportsIneligibleChecksInsteadOfClaimingUpToDate() {
        let reasons: [SPUNoUpdateFoundReason?] = [
            .systemIsTooOld, .systemIsTooNew, .hardwareDoesNotSupportARM64, .unknown, nil,
        ]
        for reason in reasons {
            let service = UpdateService()
            let driver = SparkleUpdateDriver()
            driver.service = service
            var acknowledged = false
            driver.showUpdateNotFoundWithError(
                sparkleNoUpdateError(reason: reason, recovery: "This update cannot be installed.")
            ) { acknowledged = true }
            let context = String(describing: reason)
            XCTAssertTrue(acknowledged, context)
            XCTAssertEqual(service.state, .failed("This update cannot be installed."), context)
        }
    }

    private func makePreferences() throws -> UserDefaults {
        let name = "AgentNotch.UpdateTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    func testMissingOrUnknownReasonFallsBackToDescription() {
        let reasons: [SPUNoUpdateFoundReason?] = [nil, .unknown]
        for reason in reasons {
            XCTAssertEqual(
                sparkleNoUpdateOutcome(sparkleNoUpdateError(
                    reason: reason,
                    description: "You're up to date!",
                    recovery: "  "
                )),
                .unavailable("You're up to date!")
            )
        }
    }

    /// Models packaged metadata and an embedded framework without starting a real updater.
    private func makePackagedBundle(manualUpdates: Bool) throws -> Bundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = directory.appendingPathComponent("Agent Notch.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("Frameworks/Sparkle.framework", isDirectory: true),
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.afonsoferreira.AgentNotch",
            "CFBundlePackageType": "APPL",
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "test-key",
            "AgentNotchManualUpdates": manualUpdates,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return try XCTUnwrap(Bundle(url: app))
    }
}

private func sparkleNoUpdateError(
    reason: SPUNoUpdateFoundReason?,
    description: String = "No update available.",
    recovery: String? = nil
) -> NSError {
    var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
    if let reason {
        userInfo[SPUNoUpdateFoundReasonKey] = NSNumber(value: reason.rawValue)
    }
    if let recovery {
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = recovery
    }
    return NSError(
        domain: SUSparkleErrorDomain,
        code: Int(SUError.noUpdateError.rawValue),
        userInfo: userInfo
    )
}
