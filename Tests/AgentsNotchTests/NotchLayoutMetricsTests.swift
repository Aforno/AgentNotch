@testable import AgentsNotch
import XCTest

final class NotchLayoutMetricsTests: XCTestCase {
    func testExpandedWidthFitsTheDisplayWithoutShrinkingBelowThePhysicalNotch() {
        let cases: [(name: String, screenWidth: CGFloat, expected: CGFloat)] = [
            ("room for preferred width", 1_440, 440),
            ("narrow display", 420, 388),
            ("physical notch floor", 200, 180),
        ]
        for example in cases {
            XCTAssertEqual(
                NotchLayoutMetrics.expandedWidth(
                    preferred: 440, screenWidth: example.screenWidth, notchWidth: 180
                ),
                example.expected,
                example.name
            )
        }
    }

    func testDetailAndWaitingHeightsFitContentAndAvailableDisplay() {
        let cases: [(name: String, measured: CGFloat, screen: CGFloat, detail: CGFloat, waiting: CGFloat)] = [
            ("short content", 60, 900, 164, 96),
            ("content below the caps", 210, 900, 210, 210),
            ("long content scrolls", 800, 900, 420, 300),
            ("short display", 800, 360, 312, 300),
            ("display smaller than either floor", 800, 150, 102, 102),
            ("no available display space", 800, 20, 0, 0),
        ]
        for example in cases {
            XCTAssertEqual(
                NotchLayoutMetrics.detailContentHeight(
                    measured: example.measured, screenHeight: example.screen, notchHeight: 32
                ),
                example.detail,
                example.name
            )
            XCTAssertEqual(
                NotchLayoutMetrics.waitingContentHeight(
                    measured: example.measured, screenHeight: example.screen, notchHeight: 32
                ),
                example.waiting,
                example.name
            )
        }
    }
}
