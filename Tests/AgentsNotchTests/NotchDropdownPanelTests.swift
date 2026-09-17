import AppKit
@testable import AgentsNotch
import XCTest

@MainActor
final class NotchDropdownPanelTests: XCTestCase {
    func testDropdownDismissesWhenApplicationResignsActive() async {
        let dropdown = NotchDropdownPanel()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        var didDismiss = false

        dropdown.present(
            relativeTo: anchor,
            titles: ["All"],
            selectedIndex: 0,
            onSelect: { _ in },
            onDismiss: { didDismiss = true }
        )
        XCTAssertTrue(dropdown.isPresented)

        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApplication.shared
        )
        await Task.yield()

        XCTAssertFalse(dropdown.isPresented)
        XCTAssertTrue(didDismiss)
    }

    func testDropdownDismissesWhenOwnerWindowResignsKey() async {
        let dropdown = NotchDropdownPanel()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        let owner = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        owner.contentView = anchor
        var didDismiss = false

        dropdown.present(
            relativeTo: anchor,
            titles: ["All"],
            selectedIndex: 0,
            onSelect: { _ in },
            onDismiss: { didDismiss = true }
        )
        XCTAssertTrue(dropdown.isPresented)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: owner)
        await Task.yield()

        XCTAssertFalse(dropdown.isPresented)
        XCTAssertTrue(didDismiss)
    }

    func testArrowKeysAndReturnSelectHighlightedOption() {
        let dropdown = NotchDropdownPanel()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        var selectedIndex: Int?
        dropdown.present(
            relativeTo: anchor,
            titles: ["All", "Active", "Completed"],
            selectedIndex: 0,
            onSelect: { selectedIndex = $0 },
            onDismiss: {}
        )

        XCTAssertTrue(dropdown.handleKeyCode(125))
        XCTAssertTrue(dropdown.handleKeyCode(125))
        XCTAssertTrue(dropdown.handleKeyCode(36))
        XCTAssertEqual(selectedIndex, 2)
        XCTAssertFalse(dropdown.isPresented)
    }

    func testMenuOriginDropsBelowTheAnchorWhenThereIsRoom() {
        let origin = NotchDropdownPanel.menuOrigin(
            size: NSSize(width: 168, height: 96),
            anchor: NSRect(x: 400, y: 500, width: 120, height: 28),
            screen: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        // Trailing-aligned with the anchor, one gap below it.
        XCTAssertEqual(origin.x, 400)
        XCTAssertEqual(origin.y, 400)
    }

    func testMenuOriginFlipsAboveAnchorNearTheBottomEdge() {
        let origin = NotchDropdownPanel.menuOrigin(
            size: NSSize(width: 168, height: 96),
            anchor: NSRect(x: 400, y: 40, width: 120, height: 28),
            screen: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(origin.y, 72)
    }

    func testMenuOriginPinsToTheScreenWhenNeitherSideFits() {
        let origin = NotchDropdownPanel.menuOrigin(
            size: NSSize(width: 168, height: 300),
            anchor: NSRect(x: 400, y: 120, width: 120, height: 28),
            screen: NSRect(x: 0, y: 0, width: 1_440, height: 320)
        )

        XCTAssertEqual(origin.y, 0)
    }

    func testMenuOriginClampsToTheTrailingScreenEdge() {
        let origin = NotchDropdownPanel.menuOrigin(
            size: NSSize(width: 300, height: 96),
            anchor: NSRect(x: 1_380, y: 500, width: 50, height: 28),
            screen: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(origin.x, 1_140)
    }

    func testEscapeDismissesWithoutSelection() {
        let dropdown = NotchDropdownPanel()
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        var didSelect = false
        dropdown.present(
            relativeTo: anchor,
            titles: ["All", "Active"],
            selectedIndex: 0,
            onSelect: { _ in didSelect = true },
            onDismiss: {}
        )

        XCTAssertTrue(dropdown.handleKeyCode(53))
        XCTAssertFalse(dropdown.isPresented)
        XCTAssertFalse(didSelect)
    }
}
