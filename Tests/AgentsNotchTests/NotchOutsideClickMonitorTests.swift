@testable import AgentsNotch
import XCTest

@MainActor
final class NotchOutsideClickMonitorTests: XCTestCase {
    func testClickOutsideNotchFrameDismisses() {
        let frame = CGRect(x: 100, y: 400, width: 440, height: 360)
        XCTAssertTrue(
            NotchOutsideClickMonitor.shouldDismiss(
                clickAt: CGPoint(x: 20, y: 20),
                notchFrame: frame
            )
        )
    }

    func testClickInsideNotchFrameStaysPinned() {
        let frame = CGRect(x: 100, y: 400, width: 440, height: 360)
        XCTAssertFalse(
            NotchOutsideClickMonitor.shouldDismiss(
                clickAt: CGPoint(x: 220, y: 520),
                notchFrame: frame
            )
        )
    }

    func testMissingNotchFrameDoesNotDismiss() {
        XCTAssertFalse(
            NotchOutsideClickMonitor.shouldDismiss(
                clickAt: CGPoint(x: 20, y: 20),
                notchFrame: nil
            )
        )
    }

    func testStartStopTracksActiveState() {
        let monitor = NotchOutsideClickMonitor(notchFrame: {
            CGRect(x: 0, y: 0, width: 100, height: 40)
        })
        XCTAssertFalse(monitor.isActive)

        monitor.start(onDismiss: {})
        XCTAssertTrue(monitor.isActive)

        monitor.stop()
        XCTAssertFalse(monitor.isActive)
    }
}
