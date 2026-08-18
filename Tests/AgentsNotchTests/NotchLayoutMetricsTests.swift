@testable import AgentsNotch
import XCTest

final class NotchLayoutMetricsTests: XCTestCase {
    func testExpandedWidthUsesPreferredWidthWhenItFits() {
        XCTAssertEqual(
            NotchLayoutMetrics.expandedWidth(
                preferred: 440,
                screenWidth: 1_440,
                notchWidth: 180
            ),
            440
        )
    }

    func testExpandedWidthLeavesMarginsOnNarrowDisplay() {
        XCTAssertEqual(
            NotchLayoutMetrics.expandedWidth(
                preferred: 440,
                screenWidth: 420,
                notchWidth: 180
            ),
            388
        )
    }

    func testExpandedWidthNeverShrinksBelowPhysicalNotch() {
        XCTAssertEqual(
            NotchLayoutMetrics.expandedWidth(
                preferred: 440,
                screenWidth: 200,
                notchWidth: 180
            ),
            180
        )
    }

    func testDetailHeightShrinksToCompactContent() {
        XCTAssertEqual(
            NotchLayoutMetrics.detailContentHeight(
                measured: 90,
                screenHeight: 900,
                notchHeight: 32
            ),
            NotchLayoutMetrics.minimumDetailContentHeight
        )
    }

    func testDetailHeightTracksContentUntilMaximum() {
        XCTAssertEqual(
            NotchLayoutMetrics.detailContentHeight(
                measured: 286,
                screenHeight: 900,
                notchHeight: 32
            ),
            286
        )
        XCTAssertEqual(
            NotchLayoutMetrics.detailContentHeight(
                measured: 800,
                screenHeight: 900,
                notchHeight: 32
            ),
            NotchLayoutMetrics.maximumDetailContentHeight
        )
    }

    func testDetailHeightClampsToShortDisplay() {
        XCTAssertEqual(
            NotchLayoutMetrics.detailContentHeight(
                measured: 800,
                screenHeight: 360,
                notchHeight: 32
            ),
            312
        )
        XCTAssertEqual(
            NotchLayoutMetrics.detailContentHeight(
                measured: 800,
                screenHeight: 150,
                notchHeight: 32
            ),
            102
        )
    }

    func testInsetCornerRadiusTracksOuterGeometry() {
        XCTAssertEqual(
            DynamicIslandSpacing.insetCornerRadius(outerRadius: 21),
            5
        )
        XCTAssertEqual(
            DynamicIslandSpacing.insetCornerRadius(outerRadius: 12),
            DynamicIslandSpacing.tight
        )
    }
}
