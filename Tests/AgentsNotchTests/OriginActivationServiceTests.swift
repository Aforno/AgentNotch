@testable import AgentsNotch
import AgentsNotchCore
import XCTest

final class OriginActivationServiceTests: XCTestCase {
    @MainActor
    func testOpenRejectsLocalAndCustomApplicationURLs() {
        var openedURLs: [URL] = []
        let service = OriginActivationService { url in
            openedURLs.append(url)
            return true
        }

        for url in [
            URL(fileURLWithPath: "/tmp/Untrusted.app"),
            URL(string: "cursor://open/session")!,
            URL(string: "http://example.com/session")!,
            URL(string: "https://example.com/session")!,
            URL(string: "https://chatgpt.com.example.com/session")!,
        ] {
            let session = AgentSession(event: AgentEvent(
                type: .activity,
                sessionId: "codex:unsafe-url",
                provider: .codex,
                state: .running,
                applicationURL: url
            ))

            XCTAssertFalse(service.open(session))
        }

        XCTAssertTrue(openedURLs.isEmpty)
    }

    @MainActor
    func testOpenAllowsHTTPSApplicationURL() {
        let expectedURL = URL(string: "https://chatgpt.com/codex/session/123")!
        var openedURL: URL?
        let service = OriginActivationService { url in
            openedURL = url
            return true
        }
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:https-url",
            provider: .codex,
            state: .running,
            applicationURL: expectedURL
        ))

        XCTAssertTrue(service.open(session))
        XCTAssertEqual(openedURL, expectedURL)
    }

    @MainActor
    func testCanOpenApplicationRequiresAllowlistedHTTPS() {
        let allowed = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:allowed",
            provider: .codex,
            state: .running,
            applicationURL: URL(string: "https://chatgpt.com/codex/session/123")
        ))
        let rejected = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:rejected",
            provider: .codex,
            state: .running,
            applicationURL: URL(string: "https://example.com/session")
        ))

        XCTAssertTrue(OriginActivationService.canOpenApplication(for: allowed))
        XCTAssertFalse(OriginActivationService.canOpenApplication(for: rejected))
    }

    @MainActor
    func testOpenSkipsRecycledProcessIdentifier() {
        let recordedStart = Date(timeIntervalSince1970: 100)
        var activatedPID: Int32?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in true },
            processStartedAt: { _ in recordedStart.addingTimeInterval(10) },
            activateProcess: { pid in
                activatedPID = pid
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "codex:recycled",
            provider: .codex,
            state: .waitingForUser,
            origin: AgentOrigin(
                processIdentifier: 42_424,
                processStartedAt: recordedStart
            )
        ))

        XCTAssertFalse(service.open(session))
        XCTAssertNil(activatedPID)
    }

    @MainActor
    func testOpenActivatesMatchingProcessIdentifier() {
        let recordedStart = Date(timeIntervalSince1970: 100)
        var activatedPID: Int32?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in true },
            processStartedAt: { _ in recordedStart },
            activateProcess: { pid in
                activatedPID = pid
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "codex:live",
            provider: .codex,
            state: .waitingForUser,
            origin: AgentOrigin(
                processIdentifier: 42_424,
                processStartedAt: recordedStart
            )
        ))

        XCTAssertTrue(service.open(session))
        XCTAssertEqual(activatedPID, 42_424)
    }

    @MainActor
    func testOpenActivatesLegacyPIDWhenProcessIsAlive() {
        var activatedPID: Int32?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in true },
            processStartedAt: { _ in Date() },
            activateProcess: { pid in
                activatedPID = pid
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "codex:legacy",
            provider: .codex,
            state: .waitingForUser,
            origin: AgentOrigin(processIdentifier: 42_424)
        ))

        XCTAssertTrue(service.open(session))
        XCTAssertEqual(activatedPID, 42_424)
    }

    @MainActor
    func testDestinationsIncludeSessionAndTerminalWhenBothExist() {
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:both",
            provider: .codex,
            state: .running,
            workingDirectory: "/Users/me/project",
            applicationURL: URL(string: "https://chatgpt.com/codex/session/123"),
            origin: AgentOrigin(
                bundleIdentifier: "com.apple.Terminal",
                terminalProgram: "Apple_Terminal",
                tty: "/dev/ttys001"
            )
        ))

        let destinations = OriginActivationService.destinations(for: session)
        XCTAssertEqual(destinations.map(\.action), [.application, .terminal])
        XCTAssertEqual(destinations.map(\.title), ["Open session", "Open terminal"])
        XCTAssertTrue(OriginActivationService.canOpenApplication(for: session))
        XCTAssertTrue(OriginActivationService.canOpenTerminal(for: session))
    }

    @MainActor
    func testDestinationsUseOpenAppForGraphicalOrigin() {
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "cursor:ide",
            provider: .cursor,
            state: .running,
            origin: AgentOrigin(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                terminalProgram: "vscode"
            )
        ))

        let destinations = OriginActivationService.destinations(for: session)
        XCTAssertEqual(destinations.map(\.action), [.application])
        XCTAssertEqual(destinations.map(\.title), ["Open app"])
        XCTAssertFalse(OriginActivationService.canOpenTerminal(for: session))
    }

    @MainActor
    func testOpenApplicationDoesNotFallThroughToTerminal() {
        var openedURL: URL?
        var activatedBundle: String?
        let service = OriginActivationService(
            openURL: { url in
                openedURL = url
                return true
            },
            activateBundle: { bundle in
                activatedBundle = bundle
                return true
            },
            runAppleScript: { _ in
                XCTFail("Terminal focus should not run for Open session")
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:choose-app",
            provider: .codex,
            state: .running,
            applicationURL: URL(string: "https://chatgpt.com/codex/session/123"),
            origin: AgentOrigin(
                bundleIdentifier: "com.apple.Terminal",
                terminalProgram: "Apple_Terminal",
                tty: "/dev/ttys001"
            )
        ))

        XCTAssertTrue(service.open(session, action: .application))
        XCTAssertEqual(openedURL, URL(string: "https://chatgpt.com/codex/session/123"))
        XCTAssertNil(activatedBundle)
    }

    @MainActor
    func testOpenTerminalFocusesTTYWithoutOpeningSessionURL() {
        var openedURL: URL?
        var script: String?
        let service = OriginActivationService(
            openURL: { url in
                openedURL = url
                return true
            },
            runAppleScript: { source in
                script = source
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:choose-terminal",
            provider: .codex,
            state: .running,
            applicationURL: URL(string: "https://chatgpt.com/codex/session/123"),
            origin: AgentOrigin(
                bundleIdentifier: "com.apple.Terminal",
                terminalProgram: "Apple_Terminal",
                tty: "/dev/ttys001"
            )
        ))

        XCTAssertTrue(service.open(session, action: .terminal))
        XCTAssertNil(openedURL)
        XCTAssertTrue(script?.contains("tell application \"Terminal\"") == true)
        XCTAssertTrue(script?.contains("/dev/ttys001") == true)
    }

    @MainActor
    func testOpenTerminalFallsBackToBundleWhenScriptFails() {
        var activatedBundle: String?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in false },
            activateBundle: { bundle in
                activatedBundle = bundle
                return true
            },
            runAppleScript: { _ in false }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:ghostty",
            provider: .codex,
            state: .running,
            origin: AgentOrigin(
                bundleIdentifier: "com.mitchellh.ghostty",
                terminalProgram: "ghostty"
            )
        ))

        XCTAssertTrue(service.open(session, action: .terminal))
        XCTAssertEqual(activatedBundle, "com.mitchellh.ghostty")
    }

    @MainActor
    func testOpenTerminalRejectsUnsafeTTYInAppleScript() {
        var ranScript = false
        var activatedBundle: String?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in false },
            activateBundle: { bundle in
                activatedBundle = bundle
                return true
            },
            runAppleScript: { _ in
                ranScript = true
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:unsafe-tty",
            provider: .codex,
            state: .running,
            origin: AgentOrigin(
                bundleIdentifier: "com.apple.Terminal",
                terminalProgram: "Apple_Terminal",
                tty: "/dev/ttys001\"; beep"
            )
        ))

        XCTAssertTrue(service.open(session, action: .terminal))
        XCTAssertFalse(ranScript)
        XCTAssertEqual(activatedBundle, "com.apple.Terminal")
    }

    @MainActor
    func testOpenTerminalSelectsITermSession() {
        var script: String?
        let service = OriginActivationService(
            openURL: { _ in false },
            runAppleScript: { source in
                script = source
                return true
            }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:iterm",
            provider: .codex,
            state: .running,
            origin: AgentOrigin(
                bundleIdentifier: "com.googlecode.iterm2",
                terminalProgram: "iTerm.app",
                terminalSessionIdentifier: "w0t0p0:ABCDEF12-3456-7890-ABCD-EF1234567890"
            )
        ))

        XCTAssertTrue(service.open(session, action: .terminal))
        XCTAssertTrue(script?.contains("tell application \"iTerm\"") == true)
        XCTAssertTrue(script?.contains("w0t0p0:ABCDEF12-3456-7890-ABCD-EF1234567890") == true)
    }

    @MainActor
    func testRevealRepositoryUsesWorkingDirectory() {
        var revealed: String?
        let service = OriginActivationService(
            openURL: { _ in false },
            revealDirectory: { revealed = $0 }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:repo",
            provider: .codex,
            state: .running,
            workingDirectory: "/Users/me/project"
        ))

        XCTAssertEqual(
            OriginActivationService.destinations(for: session).map(\.action),
            [.revealRepository]
        )
        XCTAssertTrue(service.open(session, action: .revealRepository))
        XCTAssertEqual(revealed, "/Users/me/project")
    }
}
