@testable import AgentsNotch
import Foundation
import XCTest

@MainActor
final class AppInstanceCoordinatorTests: XCTestCase {
    func testRepeatedLaunchHandsOffToOldestExistingInstance() {
        let recorder = ProcessActivationRecorder()
        var activationRequestProcessIdentifiers: [pid_t] = []
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
        var activationRequestProcessIdentifiers: [pid_t] = []
        let coordinator = AppInstanceCoordinator(
            currentProcessIdentifier: 30,
            runningInstances: {
                [RunningAgentNotchInstance(
                    processIdentifier: 30,
                    launchDate: Date(),
                    activate: { true }
                )]
            },
            postActivationRequest: { activationRequestProcessIdentifiers.append($0) }
        )

        XCTAssertFalse(coordinator.handOffIfNeeded())
        XCTAssertTrue(activationRequestProcessIdentifiers.isEmpty)
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
                return true
            }
        )
    }
}

@MainActor
private final class ProcessActivationRecorder {
    var processIdentifiers: [pid_t] = []
}
