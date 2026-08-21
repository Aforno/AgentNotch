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
                sessionId: "claude-code:unsafe-url",
                provider: .claudeCode,
                state: .running,
                applicationURL: url
            ))

            XCTAssertFalse(service.open(session))
        }

        XCTAssertTrue(openedURLs.isEmpty)
    }

    @MainActor
    func testOpenAllowsHTTPSApplicationURL() {
        let expectedURL = URL(string: "https://claude.ai/chat/123")!
        var openedURL: URL?
        let service = OriginActivationService { url in
            openedURL = url
            return true
        }
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "claude-code:https-url",
            provider: .claudeCode,
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
            sessionId: "claude-code:allowed",
            provider: .claudeCode,
            state: .running,
            applicationURL: URL(string: "https://claude.ai/chat/123")
        ))
        let rejected = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "claude-code:rejected",
            provider: .claudeCode,
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
            },
            openBundle: { _ in false }
        )
        let session = AgentSession(event: AgentEvent(
            type: .waiting,
            sessionId: "cursor:recycled",
            provider: .cursor,
            state: .waitingForUser,
            origin: AgentOrigin(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                processIdentifier: 42_424,
                processStartedAt: recordedStart,
                terminalProgram: "vscode"
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
            sessionId: "cursor:live",
            provider: .cursor,
            state: .waitingForUser,
            origin: AgentOrigin(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                processIdentifier: 42_424,
                processStartedAt: recordedStart,
                terminalProgram: "vscode"
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
            sessionId: "cursor:legacy",
            provider: .cursor,
            state: .waitingForUser,
            origin: AgentOrigin(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                processIdentifier: 42_424,
                terminalProgram: "vscode"
            )
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
            ),
            metadata: ["titleSource": "session"]
        ))

        let destinations = OriginActivationService.destinations(for: session)
        XCTAssertEqual(destinations.map(\.action), [.application, .terminal])
        XCTAssertEqual(destinations.map(\.title), ["Open in Codex", "Open terminal"])
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
    func testCodexSessionWithoutOriginOpensDesktopThread() {
        var openedURL: URL?
        let service = OriginActivationService(openURL: { url in
            openedURL = url
            return true
        })
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:01a020bc-310b-76c3-bd83-e7d1ac419dc9",
            provider: .codex,
            state: .running,
            workingDirectory: "/Users/me/project",
            metadata: ["titleSource": "session"]
        ))

        XCTAssertEqual(
            OriginActivationService.destinations(for: session).map(\.title),
            ["Open in Codex"]
        )
        XCTAssertTrue(service.open(session, action: .application))
        XCTAssertEqual(
            openedURL,
            URL(string: "codex://threads/01a020bc-310b-76c3-bd83-e7d1ac419dc9")
        )
    }

    @MainActor
    func testCodexDesktopThreadRejectsMalformedIdentifier() {
        var openedURL: URL?
        let service = OriginActivationService(openURL: { url in
            openedURL = url
            return true
        })
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:../../Untrusted.app",
            provider: .codex,
            state: .running,
            metadata: ["titleSource": "session"]
        ))

        XCTAssertFalse(OriginActivationService.canOpenApplication(for: session))
        XCTAssertFalse(service.open(session, action: .application))
        XCTAssertNil(openedURL)
    }

    @MainActor
    func testCodexChildOpensParentThreadInsteadOfHelperID() {
        var openedURL: URL?
        let service = OriginActivationService(openURL: { url in
            openedURL = url
            return true
        })
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:01helperulid",
            provider: .codex,
            state: .running,
            parentSessionId: "codex:01a020bc-310b-76c3-bd83-e7d1ac419dc9"
        ))

        XCTAssertEqual(
            OriginActivationService.destinations(for: session).map(\.title),
            ["Open in Codex"]
        )
        XCTAssertTrue(service.open(session, action: .application))
        XCTAssertEqual(
            openedURL,
            URL(string: "codex://threads/01a020bc-310b-76c3-bd83-e7d1ac419dc9")
        )
    }

    @MainActor
    func testCodexThreadActionSurvivesEventRingEviction() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:01a020bc-310b-76c3-bd83-e7d1ac419dc9",
            provider: .codex,
            state: .running,
            timestamp: startedAt,
            metadata: ["titleSource": "session"]
        ))
        for offset in 1...10 {
            session.apply(AgentEvent(
                type: .activity,
                sessionId: session.id,
                provider: .codex,
                state: .running,
                timestamp: startedAt.addingTimeInterval(TimeInterval(offset))
            ))
        }

        XCTAssertTrue(session.hasOfficialSessionTitle)
        XCTAssertFalse(session.recentEvents.contains { $0.metadata?["titleSource"] == "session" })
        XCTAssertEqual(
            OriginActivationService.destinations(for: session).map(\.title),
            ["Open in Codex"]
        )
    }

    @MainActor
    func testCodexInternalSessionDoesNotAdvertiseThreadAction() {
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "codex:01a02140-a957-7ea1-8be0-0569cad857bb",
            provider: .codex,
            state: .running,
            workingDirectory: "/Users/me/project"
        ))

        XCTAssertEqual(
            OriginActivationService.destinations(for: session).map(\.action),
            []
        )
    }

    @MainActor
    func testOpenCodexThreadDoesNotFallThroughToTerminalOrWeb() {
        var openedURL: URL?
        var openedBundle: String?
        let service = OriginActivationService(
            openURL: { url in
                openedURL = url
                return true
            },
            openBundle: { bundle in
                openedBundle = bundle
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
            ),
            metadata: ["titleSource": "session"]
        ))

        XCTAssertTrue(service.open(session, action: .application))
        XCTAssertEqual(openedURL, URL(string: "codex://threads/choose-app"))
        XCTAssertNil(openedBundle)
    }

    @MainActor
    func testOpenApplicationDoesNotRevealRepositoryWhenBundleFails() {
        var openedBundle: String?
        var revealedDirectory: String?
        let service = OriginActivationService(
            processAlive: { _ in false },
            openBundle: { bundle in
                openedBundle = bundle
                return false
            },
            revealDirectory: { revealedDirectory = $0 }
        )
        let session = AgentSession(event: AgentEvent(
            type: .activity,
            sessionId: "cursor:closed-app",
            provider: .cursor,
            state: .running,
            workingDirectory: "/Users/me/project",
            origin: AgentOrigin(
                bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                terminalProgram: "vscode"
            )
        ))

        XCTAssertFalse(service.open(session, action: .application))
        XCTAssertEqual(openedBundle, "com.todesktop.230313mzl4w4u92")
        XCTAssertNil(revealedDirectory)
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
    func testOpenTerminalFallsBackToBundleWhenExactFocusFails() {
        var openedBundle: String?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in false },
            openBundle: { bundle in
                openedBundle = bundle
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
        XCTAssertEqual(openedBundle, "com.mitchellh.ghostty")
    }

    @MainActor
    func testOpenTerminalRejectsUnsafeTTYInAppleScript() {
        var ranScript = false
        var openedBundle: String?
        let service = OriginActivationService(
            openURL: { _ in false },
            processAlive: { _ in false },
            openBundle: { bundle in
                openedBundle = bundle
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
        XCTAssertEqual(openedBundle, "com.apple.Terminal")
    }

    @MainActor
    func testOpenTerminalUsesITermRevealURL() throws {
        var openedURL: URL?
        let service = OriginActivationService(
            openURL: { url in
                openedURL = url
                return true
            },
            runAppleScript: { _ in
                XCTFail("iTerm session reveal should not use AppleScript")
                return false
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
        XCTAssertEqual(openedURL?.scheme, "iterm2")
        XCTAssertEqual(openedURL?.path, "/reveal")
        XCTAssertTrue(openedURL?.absoluteString.hasPrefix("iterm2:///reveal?") == true)
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(openedURL), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "sessionid" }?
                .value,
            "w0t0p0:ABCDEF12-3456-7890-ABCD-EF1234567890"
        )
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
            sessionId: "simulator:repo",
            provider: .simulator,
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
