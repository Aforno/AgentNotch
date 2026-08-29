@testable import AgentsNotch
import XCTest

final class NotchPanelControllerTests: XCTestCase {
    @MainActor
    func testPanelKeepsHostingViewBehindAppKitSizingBoundary() throws {
        let controller = NotchPanelController(runtime: AppRuntime(monitorProviders: false))
        let contentView = try XCTUnwrap(controller.window?.contentView)

        XCTAssertTrue(contentView is NotchPanelContentView)
        XCTAssertEqual(contentView.subviews.count, 1)
        XCTAssertEqual(contentView.subviews[0].autoresizingMask, [.width, .height])
        XCTAssertEqual(contentView.subviews[0].frame, contentView.bounds)
    }

    @MainActor
    func testSurfaceAvailabilityCallbackTracksPreferenceChanges() {
        let defaults = UserDefaults.standard
        let originalNotchEnabled = defaults.object(forKey: "notchEnabled")
        let originalVirtualNotch = defaults.object(forKey: "showVirtualNotch")
        let originalDisplayPreference = defaults.object(forKey: "displayPreference")
        defer {
            restore(originalNotchEnabled, forKey: "notchEnabled", in: defaults)
            restore(originalVirtualNotch, forKey: "showVirtualNotch", in: defaults)
            restore(originalDisplayPreference, forKey: "displayPreference", in: defaults)
        }

        defaults.set(true, forKey: "notchEnabled")
        defaults.set(true, forKey: "showVirtualNotch")
        defaults.set(DisplayPreference.primary.rawValue, forKey: "displayPreference")

        let controller = NotchPanelController(runtime: AppRuntime(monitorProviders: false))
        var availability: [Bool] = []
        controller.onSurfaceAvailabilityChanged = { availability.append($0) }

        defaults.set(false, forKey: "notchEnabled")
        controller.refreshPreferences()

        XCTAssertEqual(availability, [true, false])
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
