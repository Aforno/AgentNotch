@testable import AgentsNotch
import Foundation
import XCTest

final class OpenCodePluginTemplateTests: XCTestCase {
    private let relayURL = URL(fileURLWithPath: "/opt/homebrew/bin/agentnotch-hook")

    func testTemplateEmbedsRelayPathAndProviderFlag() throws {
        let source = String(decoding: OpenCodePluginTemplate.data(relayURL: relayURL), as: UTF8.self)

        XCTAssertTrue(source.contains(relayURL.path), "generated bridge must point at the bundled relay")
        XCTAssertTrue(source.contains("--provider"), "relay must be told which provider it observes")
        XCTAssertTrue(source.contains("opencode"), "provider flag value must be opencode")
    }

    func testTemplateCoversLifecycleEvents() throws {
        let source = String(decoding: OpenCodePluginTemplate.data(relayURL: relayURL), as: UTF8.self)

        // The hook_event_name values are the mapper's compatibility contract.
        for eventName in ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "PermissionRequest"] {
            XCTAssertTrue(source.contains(eventName), "missing mapping for \(eventName)")
        }
        XCTAssertTrue(source.contains("session.created"))
        XCTAssertTrue(source.contains("permission.ask"))
        XCTAssertTrue(source.contains("tool.execute.before"))
    }

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
