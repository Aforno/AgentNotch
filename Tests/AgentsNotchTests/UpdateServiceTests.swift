@testable import AgentsNotch
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
}
