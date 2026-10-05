@testable import AgentsNotch
import XCTest

@MainActor
final class NotchOutsideClickMonitorTests: XCTestCase {
    func testOnlyClicksOutsideAKnownNotchFrameDismiss() {
        let frame = CGRect(x: 100, y: 400, width: 440, height: 360)
        let cases: [(name: String, click: CGPoint, frame: CGRect?, dismiss: Bool)] = [
            ("outside", CGPoint(x: 20, y: 20), frame, true),
            ("inside", CGPoint(x: 220, y: 520), frame, false),
            ("missing frame", CGPoint(x: 20, y: 20), nil, false),
        ]
        for example in cases {
            XCTAssertEqual(
                NotchOutsideClickMonitor.shouldDismiss(clickAt: example.click, notchFrame: example.frame),
                example.dismiss,
                example.name
            )
        }
    }
}
