@testable import AgentsNotchCore
import XCTest

final class AgentOriginTests: XCTestCase {
    func testCapturedReadsTerminalEnvironmentAndTTYFallback() {
        let origin = AgentOrigin.captured(
            environment: [
                "TERM_PROGRAM": "Apple_Terminal",
                "TERM_SESSION_ID": "ABC-123",
            ],
            processIdentifier: 99,
            processStartedAt: { _ in Date(timeIntervalSince1970: 10) },
            controllingTTY: { pid in
                XCTAssertEqual(pid, 99)
                return "/dev/ttys012"
            }
        )

        XCTAssertEqual(origin?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(origin?.processIdentifier, 99)
        XCTAssertEqual(origin?.processStartedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(origin?.terminalProgram, "Apple_Terminal")
        XCTAssertEqual(origin?.terminalSessionIdentifier, "ABC-123")
        XCTAssertEqual(origin?.tty, "/dev/ttys012")
        XCTAssertEqual(origin?.isTerminalEmulator, Optional(true))
        XCTAssertEqual(origin?.isGraphicalApplication, Optional(false))
    }

    func testCapturedPrefersExplicitTTYAndBundleOverride() {
        let origin = AgentOrigin.captured(
            environment: [
                "TERM_PROGRAM": "vscode",
                "AGENTS_NOTCH_BUNDLE_IDENTIFIER": "com.todesktop.230313mzl4w4u92",
                "TTY": "/dev/ttys003",
                "TERM_SESSION_ID": "vscode-session",
            ],
            processIdentifier: 7,
            processStartedAt: { _ in nil },
            controllingTTY: { _ in
                XCTFail("TTY environment should win")
                return "/dev/ttys999"
            }
        )

        XCTAssertEqual(origin?.bundleIdentifier, "com.todesktop.230313mzl4w4u92")
        XCTAssertEqual(origin?.tty, "/dev/ttys003")
        XCTAssertEqual(origin?.isGraphicalApplication, Optional(true))
        XCTAssertEqual(origin?.isTerminalEmulator, Optional(false))
    }

    func testVSCodeIntegratedTerminalIsNotATerminalEmulator() {
        let origin = AgentOrigin(
            bundleIdentifier: "com.microsoft.VSCode",
            terminalProgram: "vscode",
            tty: "/dev/ttys004"
        )
        XCTAssertTrue(origin.isGraphicalApplication)
        XCTAssertFalse(origin.isTerminalEmulator)
    }

    func testTTYPathIgnoresMissingDevices() {
        XCTAssertNil(AgentProcessIdentity.ttyPath(fromDevice: 0))
        XCTAssertNil(AgentProcessIdentity.ttyPath(fromDevice: UInt32.max))
    }
}
