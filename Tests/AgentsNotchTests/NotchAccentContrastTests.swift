@testable import AgentsNotch
import AppKit
import XCTest

final class NotchAccentContrastTests: XCTestCase {
    func testBlueAccentKeepsWhiteForeground() {
        let blue = NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)
        XCTAssertFalse(NotchAccentContrast.usesDarkForeground(for: blue))
        XCTAssertEqual(NotchAccentContrast.foreground(for: blue), .white)
    }

    func testPinkAccentKeepsWhiteForeground() {
        let pink = NSColor(srgbRed: 1, green: 0.176, blue: 0.333, alpha: 1)
        XCTAssertFalse(NotchAccentContrast.usesDarkForeground(for: pink))
        XCTAssertEqual(NotchAccentContrast.foreground(for: pink), .white)
    }

    func testRedAccentKeepsWhiteForeground() {
        let red = NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)
        XCTAssertFalse(NotchAccentContrast.usesDarkForeground(for: red))
    }

    func testYellowAccentUsesBlackForeground() {
        let yellow = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        XCTAssertTrue(NotchAccentContrast.usesDarkForeground(for: yellow))
        XCTAssertEqual(NotchAccentContrast.foreground(for: yellow), .black)
    }

    func testGreenAccentUsesBlackForeground() {
        let green = NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        XCTAssertTrue(NotchAccentContrast.usesDarkForeground(for: green))
        XCTAssertEqual(NotchAccentContrast.foreground(for: green), .black)
    }

    func testOrangeAccentUsesBlackForeground() {
        let orange = NSColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1)
        XCTAssertTrue(NotchAccentContrast.usesDarkForeground(for: orange))
        XCTAssertEqual(NotchAccentContrast.foreground(for: orange), .black)
    }

    func testBlendedLuminanceIsSourceTimesFillOpacityOverBlack() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let expected = NotchAccentContrast.relativeLuminance(red: 0.9, green: 0.9, blue: 0.9)
        XCTAssertEqual(
            NotchAccentContrast.blendedRelativeLuminance(of: white),
            expected,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            NotchAccentContrast.blendedRelativeLuminance(of: .black),
            0,
            accuracy: 0.0001
        )
    }
}
