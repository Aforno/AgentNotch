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
