@testable import AgentsNotchCore
@testable import AgentsNotchHook
import Darwin
import Foundation
import XCTest

/// Locks the relay's stdout contract documented in docs/PROTOCOL.md: passive
/// runs print `{}` for every provider except Claude (which requires empty
/// stdout), and decisions are newline-terminated single-line JSON.
final class HookPassiveResponseContractTests: XCTestCase {
    private func capture(_ body: (Int32) -> Void) -> Data {
        var fds: [Int32] = [-1, -1]
        XCTAssertEqual(pipe(&fds), 0)
        defer {
            close(fds[0])
        }
        body(fds[1])
        close(fds[1])

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = read(fds[0], &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func testPassiveResponseIsEmptyJSONObjectForMostProviders() throws {
        for provider in [AgentProvider.codex, .grok, .openCode, .geminiCLI, .cursor] {
            let output = capture { HookProcessIO.writePassiveResponse(for: provider, to: $0) }
            XCTAssertEqual(String(decoding: output, as: UTF8.self), "{}\n", "provider \(provider.rawValue)")
        }
    }

    func testPassiveResponseIsSilentForClaudeCode() {
        let output = capture { HookProcessIO.writePassiveResponse(for: .claudeCode, to: $0) }
        XCTAssertTrue(output.isEmpty, "Claude Code hooks must not write to stdout when passive")
    }

    func testDecisionIsNewlineTerminated() {
        let withoutNewline = capture {
            HookProcessIO.writeDecision(Data("{\"decision\":1}".utf8), to: $0)
        }
        XCTAssertEqual(String(decoding: withoutNewline, as: UTF8.self), "{\"decision\":1}\n")

        let alreadyTerminated = capture {
            HookProcessIO.writeDecision(Data("{\"decision\":1}\n".utf8), to: $0)
        }
        XCTAssertEqual(String(decoding: alreadyTerminated, as: UTF8.self), "{\"decision\":1}\n")
    }
}
