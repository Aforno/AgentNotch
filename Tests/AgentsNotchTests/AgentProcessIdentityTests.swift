@testable import AgentsNotchCore
import Foundation
import XCTest

final class AgentProcessIdentityTests: XCTestCase {
    func testHookShellWrapperResolvesToTheAgentAndItsArguments() throws {
        // Stand-in for Cursor: this test process runs a hook via `sh -c`.
        let wrapper = Process()
        wrapper.executableURL = URL(fileURLWithPath: "/bin/sh")
        wrapper.arguments = ["-c", "sleep 5; true"]
        try wrapper.run()
        defer { wrapper.terminate() }

        let me = ProcessInfo.processInfo.processIdentifier
        XCTAssertEqual(AgentProcessIdentity.agentProcess(forHookParent: wrapper.processIdentifier), me)
        XCTAssertEqual(AgentProcessIdentity.agentProcess(forHookParent: me), me)
        XCTAssertEqual(
            AgentProcessIdentity.arguments(for: wrapper.processIdentifier),
            ["/bin/sh", "-c", "sleep 5; true"]
        )
    }
}
