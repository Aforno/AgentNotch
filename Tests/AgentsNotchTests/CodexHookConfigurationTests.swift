import AgentsNotchCore
import XCTest

final class CodexHookConfigurationTests: XCTestCase {
    func testSessionEndUsesCodexMaximumTimeout() {
        XCTAssertEqual(CodexHookConfiguration.timeout(for: "SessionEnd"), 3)
    }

    func testOtherEventsKeepNormalRelayTimeout() {
        XCTAssertEqual(CodexHookConfiguration.timeout(for: "PreToolUse"), 5)
    }
}
