@testable import AgentsNotch
import Foundation
import XCTest

@MainActor
final class AppInstanceCoordinatorTests: XCTestCase {
    func testRepeatedLaunchHandsOffToOldestExistingInstance() {
        let recorder = ProcessActivationRecorder()
        var activationRequestProcessIdentifiers: [pid_t?] = []
        let coordinator = AppInstanceCoordinator(
            currentProcessIdentifier: 30,
            runningInstances: {
                [
                    self.instance(30, launchedAt: 30, recorder: recorder),
                    self.instance(20, launchedAt: 20, recorder: recorder),
                    self.instance(10, launchedAt: 10, recorder: recorder),
                ]
            },
            postActivationRequest: { activationRequestProcessIdentifiers.append($0) }
        )

        XCTAssertTrue(coordinator.handOffIfNeeded())
        XCTAssertEqual(recorder.processIdentifiers, [10])
        XCTAssertEqual(activationRequestProcessIdentifiers, [10])
    }

    func testFirstLaunchContinuesWithoutPostingActivationRequest() {
        var activationRequestProcessIdentifiers: [pid_t?] = []
        let coordinator = AppInstanceCoordinator(
            currentProcessIdentifier: 30,
            runningInstances: {
                [RunningAgentNotchInstance(
                    processIdentifier: 30,
                    launchDate: Date(),
                    activate: {}
                )]
            },
            postActivationRequest: { activationRequestProcessIdentifiers.append($0) }
        )

        XCTAssertFalse(coordinator.handOffIfNeeded())
        XCTAssertTrue(activationRequestProcessIdentifiers.isEmpty)
    }

    func testNewerVisiblePeerIsNotTreatedAsExistingInstance() {
        let recorder = ProcessActivationRecorder()
        var activationRequestProcessIdentifiers: [pid_t?] = []
        let coordinator = AppInstanceCoordinator(
            currentProcessIdentifier: 10,
            runningInstances: {
                [
                    self.instance(10, launchedAt: 10, recorder: recorder),
                    self.instance(20, launchedAt: 20, recorder: recorder),
                ]
            },
            postActivationRequest: { activationRequestProcessIdentifiers.append($0) }
        )

        XCTAssertFalse(coordinator.handOffIfNeeded())
        XCTAssertTrue(recorder.processIdentifiers.isEmpty)
        XCTAssertTrue(activationRequestProcessIdentifiers.isEmpty)
    }

    func testOverlappingLaunchesOnlyTheNewerProcessHandsOff() {
        let recorder = ProcessActivationRecorder()
        var olderActivationRequests: [pid_t?] = []
        var newerActivationRequests: [pid_t?] = []
        let instances = {
            [
                self.instance(10, launchedAt: 10, recorder: recorder),
                self.instance(20, launchedAt: 20, recorder: recorder),
            ]
        }
        let older = AppInstanceCoordinator(
            currentProcessIdentifier: 10,
            runningInstances: instances,
            postActivationRequest: { olderActivationRequests.append($0) }
        )
        let newer = AppInstanceCoordinator(
            currentProcessIdentifier: 20,
            runningInstances: instances,
            postActivationRequest: { newerActivationRequests.append($0) }
        )

        XCTAssertFalse(older.handOffIfNeeded())
        XCTAssertTrue(newer.handOffIfNeeded())
        XCTAssertEqual(recorder.processIdentifiers, [10])
        XCTAssertTrue(olderActivationRequests.isEmpty)
        XCTAssertEqual(newerActivationRequests, [10])
    }

    func testLostOwnershipLockHandsOffEvenToANewerPeer() {
        let recorder = ProcessActivationRecorder()
        var activationRequestProcessIdentifiers: [pid_t?] = []
        let coordinator = AppInstanceCoordinator(
            currentProcessIdentifier: 10,
            runningInstances: {
                [
                    self.instance(10, launchedAt: 10, recorder: recorder),
                    self.instance(20, launchedAt: 20, recorder: recorder),
                ]
            },
            postActivationRequest: { activationRequestProcessIdentifiers.append($0) },
            tryAcquireOwnership: { false }
        )

        XCTAssertTrue(coordinator.handOffIfNeeded())
        XCTAssertEqual(recorder.processIdentifiers, [20])
        XCTAssertEqual(activationRequestProcessIdentifiers, [20])
    }

    func testLostOwnershipLockWithoutVisiblePeerStillHandsOff() {
        var activationRequestProcessIdentifiers: [pid_t?] = []
        let coordinator = AppInstanceCoordinator(
            currentProcessIdentifier: 10,
            runningInstances: {
                [
                    RunningAgentNotchInstance(
                        processIdentifier: 10,
                        launchDate: Date(timeIntervalSince1970: 10),
                        activate: {}
                    )
                ]
            },
            postActivationRequest: { activationRequestProcessIdentifiers.append($0) },
            tryAcquireOwnership: { false }
        )

        XCTAssertTrue(coordinator.handOffIfNeeded())
        XCTAssertEqual(activationRequestProcessIdentifiers, [nil])
    }

    private func instance(
        _ processIdentifier: pid_t,
        launchedAt: TimeInterval,
        recorder: ProcessActivationRecorder
    ) -> RunningAgentNotchInstance {
        RunningAgentNotchInstance(
            processIdentifier: processIdentifier,
            launchDate: Date(timeIntervalSince1970: launchedAt),
            activate: {
                recorder.processIdentifiers.append(processIdentifier)
            }
        )
    }
}

@MainActor
private final class ProcessActivationRecorder {
    var processIdentifiers: [pid_t] = []
}
