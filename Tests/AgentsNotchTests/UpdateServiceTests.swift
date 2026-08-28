@testable import AgentsNotch
import Sparkle
import XCTest

final class UpdateStateMachineTests: XCTestCase {
    func testBackgroundCheckThenDownloadThenRestart() {
        var state = UpdateState.idle
        state = reduceUpdateState(state, .checkStarted)
        XCTAssertEqual(state, .checking)
        state = reduceUpdateState(state, .updateAvailable(version: "0.3.0"))
        XCTAssertEqual(state, .available(version: "0.3.0"))
        state = reduceUpdateState(state, .downloadStarted)
        XCTAssertEqual(state, .downloading(version: "0.3.0", percent: 0))
        state = reduceUpdateState(state, .downloadProgress(0.42))
        XCTAssertEqual(state, .downloading(version: "0.3.0", percent: 0.42))
        state = reduceUpdateState(state, .downloadComplete)
        XCTAssertEqual(state, .downloaded(version: "0.3.0"))
        state = reduceUpdateState(state, .installStarted)
        XCTAssertEqual(state, .installing(version: "0.3.0"))
    }

    func testDownloadFailureReturnsToAvailable() {
        var state = UpdateState.available(version: "0.3.0")
        state = reduceUpdateState(state, .downloadStarted)
        state = reduceUpdateState(state, .downloadFailed("network down"))
        XCTAssertEqual(state, .available(version: "0.3.0"))
    }

    func testInstallFailureKeepsDownloadedUpdate() {
        var state = UpdateState.downloaded(version: "0.3.0")
        state = reduceUpdateState(state, .installStarted)
        state = reduceUpdateState(state, .installFailed("relaunch failed"))
        XCTAssertEqual(state, .downloaded(version: "0.3.0"))
    }

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
    func testUnpackagedHostDoesNotUseSparkle() {
        XCTAssertFalse(UpdateService.hostCanUseSparkle)
        let service = UpdateService()
        service.start()
        XCTAssertEqual(service.state, .unavailable(UpdateService.packagedOnlyMessage))
    }

    @MainActor
    func testDownloadAndInstallAreNoOpsWithoutSparkleSession() {
        let service = UpdateService()
        service.start()
        service.download()
        service.install()
        XCTAssertEqual(service.state, .unavailable(UpdateService.packagedOnlyMessage))
    }

    @MainActor
    func testCheckPresentsStatusSurface() {
        let service = UpdateService()
        var presented = false
        service.presentStatus = { presented = true }
        service.check()
        XCTAssertTrue(presented)
        XCTAssertEqual(service.state, .unavailable(UpdateService.packagedOnlyMessage))
    }

    @MainActor
    func testDriverTreatsLatestVersionAsUpToDate() {
        let service = UpdateService()
        let driver = SparkleUpdateDriver()
        driver.service = service
        var acknowledged = false
        driver.showUpdateNotFoundWithError(sparkleNoUpdateError(reason: .onLatestVersion)) {
            acknowledged = true
        }
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(service.state, .upToDate)
    }

    @MainActor
    func testDriverSurfacesIneligibleUpdate() {
        let service = UpdateService()
        let driver = SparkleUpdateDriver()
        driver.service = service
        driver.showUpdateNotFoundWithError(
            sparkleNoUpdateError(
                reason: .systemIsTooOld,
                recovery: "0.3.0 is available but your macOS version is too old to install it."
            )
        ) {}
        XCTAssertEqual(
            service.state,
            .failed("0.3.0 is available but your macOS version is too old to install it.")
        )
        XCTAssertEqual(
            service.lastError,
            "0.3.0 is available but your macOS version is too old to install it."
        )
    }

    @MainActor
    func testShowUpdateInFocusPresentsStatusSurface() {
        let service = UpdateService()
        let driver = SparkleUpdateDriver()
        driver.service = service
        var presented = false
        service.presentStatus = { presented = true }
        driver.showUpdateInFocus()
        XCTAssertTrue(presented)
    }
}

final class SparkleNoUpdateOutcomeTests: XCTestCase {
    func testOnLatestVersionIsCurrent() {
        XCTAssertEqual(
            sparkleNoUpdateOutcome(sparkleNoUpdateError(reason: .onLatestVersion)),
            .currentVersion
        )
    }

    func testNewerThanLatestIsCurrent() {
        XCTAssertEqual(
            sparkleNoUpdateOutcome(sparkleNoUpdateError(reason: .onNewerThanLatestVersion)),
            .currentVersion
        )
    }

    func testSystemTooOldSurfacesSparkleMessage() {
        let error = sparkleNoUpdateError(
            reason: .systemIsTooOld,
            description: "No update found.",
            recovery: "0.3.0 is available but your macOS version is too old to install it."
        )
        XCTAssertEqual(
            sparkleNoUpdateOutcome(error),
            .unavailable("0.3.0 is available but your macOS version is too old to install it.")
        )
    }

    func testSystemTooNewSurfacesSparkleMessage() {
        XCTAssertEqual(
            sparkleNoUpdateOutcome(
                sparkleNoUpdateError(
                    reason: .systemIsTooNew,
                    recovery: "This update only supports up to macOS 14."
                )
            ),
            .unavailable("This update only supports up to macOS 14.")
        )
    }

    func testUnknownReasonIsNotUpToDate() {
        XCTAssertEqual(
            sparkleNoUpdateOutcome(
                sparkleNoUpdateError(reason: .unknown, description: "No valid update information could be loaded.")
            ),
            .unavailable("No valid update information could be loaded.")
        )
    }

    func testMissingReasonIsNotUpToDate() {
        XCTAssertEqual(
            sparkleNoUpdateOutcome(
                sparkleNoUpdateError(reason: nil, description: "You're up to date!")
            ),
            .unavailable("You're up to date!")
        )
    }

    func testRecoverySuggestionBeatsDescription() {
        XCTAssertEqual(
            sparkleNoUpdateOutcome(
                sparkleNoUpdateError(
                    reason: .hardwareDoesNotSupportARM64,
                    description: "Update Error!",
                    recovery: "0.3.0 is available but this update requires a new Apple silicon Mac."
                )
            ),
            .unavailable("0.3.0 is available but this update requires a new Apple silicon Mac.")
        )
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
