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
        let originalNotchEnabled = defaults.object(forKey: AppPreferences.Key.notchEnabled)
        let originalVirtualNotch = defaults.object(forKey: AppPreferences.Key.showVirtualNotch)
        let originalDisplayPreference = defaults.object(forKey: AppPreferences.Key.displayPreference)
        defer {
            restore(originalNotchEnabled, forKey: AppPreferences.Key.notchEnabled, in: defaults)
            restore(originalVirtualNotch, forKey: AppPreferences.Key.showVirtualNotch, in: defaults)
            restore(originalDisplayPreference, forKey: AppPreferences.Key.displayPreference, in: defaults)
        }

        defaults.set(true, forKey: AppPreferences.Key.notchEnabled)
        defaults.set(true, forKey: AppPreferences.Key.showVirtualNotch)
        defaults.set(DisplayPreference.primary.rawValue, forKey: AppPreferences.Key.displayPreference)

        let controller = NotchPanelController(runtime: AppRuntime(monitorProviders: false))
        var availability: [Bool] = []
        controller.onSurfaceAvailabilityChanged = { availability.append($0) }

        defaults.set(false, forKey: AppPreferences.Key.notchEnabled)
        controller.refreshPreferences()

        XCTAssertEqual(availability, [true, false])
    }

    @MainActor
    func testDisplayResolverRespectsNotchPreference() {
        let defaults = UserDefaults.standard
        let originalDisplayPreference = defaults.object(forKey: AppPreferences.Key.displayPreference)
        defer {
            restore(originalDisplayPreference, forKey: AppPreferences.Key.displayPreference, in: defaults)
        }

        defaults.set(DisplayPreference.notch.rawValue, forKey: AppPreferences.Key.displayPreference)
        XCTAssertEqual(DisplayPreference.notch.title, "Display with notch")

        let preferred = DisplayResolver.preferredScreen()
        let expected = NSScreen.screens.first { DisplayGeometry.detect(on: $0).hasPhysicalNotch }
            ?? NSScreen.screens.first
            ?? NSScreen.main
        XCTAssertEqual(preferred, expected)
    }

    @MainActor
    func testPointerDisplayObservationTogglesWithPreference() {
        let defaults = UserDefaults.standard
        let originalDisplayPreference = defaults.object(forKey: AppPreferences.Key.displayPreference)
        defer {
            restore(originalDisplayPreference, forKey: AppPreferences.Key.displayPreference, in: defaults)
        }

        defaults.set(DisplayPreference.pointer.rawValue, forKey: AppPreferences.Key.displayPreference)
        let controller = NotchPanelController(runtime: AppRuntime(monitorProviders: false))

        defaults.set(DisplayPreference.primary.rawValue, forKey: AppPreferences.Key.displayPreference)
        controller.refreshPreferences()

        defaults.set(DisplayPreference.notch.rawValue, forKey: AppPreferences.Key.displayPreference)
        controller.refreshPreferences()
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
