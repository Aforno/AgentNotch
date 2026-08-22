@testable import AgentsNotchCore
@testable import AgentsNotchHook
import Foundation
import XCTest

final class HookProcessInvocationTests: XCTestCase {
    func testKnownProviderIsAccepted() {
        let warnings: [String] = []
        let invocation = HookProcessInvocation.parse(
            arguments: ["AgentsNotchHook", "--provider", "claude-code"],
            environment: [:],
            warn: { _ in XCTFail("known provider must not warn") }
        )
        XCTAssertEqual(invocation.configuredProvider, .claudeCode)
        XCTAssertTrue(warnings.isEmpty)
    }

    func testMissingProviderFallsBackToCodexSilently() {
        let invocation = HookProcessInvocation.parse(
            arguments: ["AgentsNotchHook"],
            environment: [:],
            warn: { _ in XCTFail("absent --provider must not warn") }
        )
        XCTAssertEqual(invocation.configuredProvider, .codex)
    }

    func testUnknownProviderWarnsAndFallsBackToCodex() {
        var warnings: [String] = []
        let invocation = HookProcessInvocation.parse(
            arguments: ["AgentsNotchHook", "--provider", "codxe"],
            environment: [:],
            warn: { warnings.append($0) }
        )
        XCTAssertEqual(invocation.configuredProvider, .codex)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("codxe"))
    }

    func testProviderWithoutValueDoesNotCrash() {
        let invocation = HookProcessInvocation.parse(
            arguments: ["AgentsNotchHook", "--provider"],
            environment: [:],
            warn: { _ in XCTFail("dangling flag must not warn") }
        )
        XCTAssertEqual(invocation.configuredProvider, .codex)
    }

    func testSocketPathArgumentsAreHonored() {
        let invocation = HookProcessInvocation.parse(
            arguments: [
                "AgentsNotchHook",
                "--socket", "/tmp/event-test.sock",
                "--reply-socket", "/tmp/reply-test.sock",
                "--answer",
                "--self-test",
            ],
            environment: [:]
        )
        XCTAssertEqual(invocation.socketURL.path, "/tmp/event-test.sock")
        XCTAssertEqual(invocation.replySocketURL.path, "/tmp/reply-test.sock")
        XCTAssertTrue(invocation.answersFromNotch)
        XCTAssertTrue(invocation.isSelfTest)
    }

    func testGrokEnvironmentRoutesProviderWithoutExplicitFlag() {
        let invocation = HookProcessInvocation.parse(
            arguments: ["AgentsNotchHook"],
            environment: ["GROK_HOOK_EVENT": "UserPromptSubmit"]
        )
        XCTAssertEqual(invocation.provider, .grok)
        // configured stays codex because the Claude compatibility hook installs
        // no --provider flag; routing happens through the environment.
        XCTAssertEqual(invocation.configuredProvider, .codex)
    }
}
