@testable import AgentsNotch
import Foundation
import XCTest

final class OpenCodePluginTemplateTests: XCTestCase {
    private let relayURL = URL(fileURLWithPath: "/opt/homebrew/bin/agentnotch-hook")

    func testOwnershipDetection() throws {
        let owned = OpenCodePluginTemplate.data(relayURL: relayURL)
        XCTAssertTrue(OpenCodePluginTemplate.isOwned(owned))

        let foreign = Data("// my custom plugin\nexport const AgentNotchPlugin = 1\n".utf8)
        XCTAssertFalse(
            OpenCodePluginTemplate.isOwned(foreign),
            "user-edited files must not be detected as app-owned"
        )
    }
}
