@testable import AgentsNotch
import AppKit
import XCTest

final class NotchAccentContrastTests: XCTestCase {
    func testEveryAccentAndInteractionFillMeetsSmallTextContrast() {
        let accents: [(String, NSColor)] = [
            ("blue", NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)),
            ("pink", NSColor(srgbRed: 1, green: 0.176, blue: 0.333, alpha: 1)),
            ("red", NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 1)),
            ("yellow", NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)),
            ("green", NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1)),
            ("orange", NSColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1)),
        ]
        let fillOpacities: [(String, CGFloat)] = [
            ("rest", NotchAccentContrast.primaryFillOpacity),
            ("hover", 1),
            ("pressed", 0.72),
        ]

        for (accentName, accent) in accents {
            for (stateName, fillOpacity) in fillOpacities {
                XCTAssertGreaterThanOrEqual(
                    NotchAccentContrast.preferredContrastRatio(
                        for: accent,
                        fillOpacity: fillOpacity
                    ),
                    4.5,
                    "\(accentName) \(stateName)"
                )
            }
        }
    }

    func testForegroundTracksTheCurrentFillInsteadOfOnlyTheRestingFill() {
        let blue = NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)

        XCTAssertEqual(
            NotchAccentContrast.foreground(for: blue, fillOpacity: 0.9),
            .white
        )
        XCTAssertEqual(
            NotchAccentContrast.foreground(for: blue, fillOpacity: 1),
            .black
        )
    }

}
