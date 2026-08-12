@testable import AgentsNotch
import XCTest

@MainActor
final class NotchPanelFrameSchedulerTests: XCTestCase {
    func testSchedulerAppliesLatestUpdate() async {
        let applied = expectation(description: "latest frame applied")
        var received: (CGSize, Bool)?
        let scheduler = NotchPanelFrameScheduler { size, animated in
            received = (size, animated)
            applied.fulfill()
        }

        scheduler.schedule(size: CGSize(width: 100, height: 30), animated: false)
        scheduler.schedule(size: CGSize(width: 280, height: 180), animated: true)

        await fulfillment(of: [applied], timeout: 1)
        XCTAssertEqual(received?.0, CGSize(width: 280, height: 180))
        XCTAssertEqual(received?.1, true)
    }
}
