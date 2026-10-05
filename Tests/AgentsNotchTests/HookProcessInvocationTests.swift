@testable import AgentsNotchCore
@testable import AgentsNotchHook
import Foundation
import XCTest

final class HookProcessInvocationTests: XCTestCase {
    func testProviderParsingPreservesUnknownIDsAndWarnsOnlyForUnknownValues() {
        let cases: [(arguments: [String], provider: AgentProvider, warns: Bool)] = [
            (["--provider", "claude-code"], .claudeCode, false),
            ([], .codex, false),
            (["--provider"], .codex, false),
            (["--provider", "codxe"], AgentProvider(rawValue: "codxe"), true),
        ]
        for example in cases {
            var warnings: [String] = []
            let invocation = HookProcessInvocation.parse(
                arguments: ["AgentsNotchHook"] + example.arguments,
                environment: [:],
                warn: { warnings.append($0) }
            )
            let context = example.arguments.joined(separator: " ")
            XCTAssertEqual(invocation.configuredProvider, example.provider, context)
            XCTAssertEqual(invocation.provider, example.provider, context)
            XCTAssertEqual(warnings.count, example.warns ? 1 : 0, context)
            if example.warns {
                XCTAssertEqual(warnings.first?.contains(example.provider.rawValue), true, context)
            }
        }
    }

    func testEventFlagAcceptsAValueAndIgnoresADanglingFlag() {
        let events: [String?] = ["PreToolUse", nil]
        for event in events {
            let invocation = HookProcessInvocation.parse(
                arguments: ["AgentsNotchHook", "--provider", "antigravity", "--event"] + (event.map { [$0] } ?? []),
                environment: [:],
                warn: { XCTFail($0) }
            )
            XCTAssertEqual(invocation.eventName, event)
        }
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
        XCTAssertEqual(invocation.configuredProvider, .codex)
    }
}
