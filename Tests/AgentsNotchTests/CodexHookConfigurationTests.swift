import AgentsNotchCore
import XCTest

final class CodexHookConfigurationTests: XCTestCase {
    func testSessionEndUsesCodexMaximumTimeout() {
        XCTAssertEqual(CodexHookConfiguration.timeout(for: "SessionEnd"), .seconds(3))
    }

    func testOtherEventsKeepNormalRelayTimeout() {
        XCTAssertEqual(CodexHookConfiguration.timeout(for: "PreToolUse"), .seconds(5))
    }
}
