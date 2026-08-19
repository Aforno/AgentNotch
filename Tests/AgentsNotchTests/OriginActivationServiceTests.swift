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
}
