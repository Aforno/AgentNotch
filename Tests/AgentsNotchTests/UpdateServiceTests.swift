@testable import AgentsNotch
import XCTest

final class UpdateServiceTests: XCTestCase {
    @MainActor
    func testOpenAvailableReleaseAlwaysUsesOfficialGitHubPage() {
        var openedURL: URL?
        let service = UpdateService { openedURL = $0 }

        service.openAvailableRelease()

        XCTAssertEqual(
            openedURL,
            URL(string: "https://github.com/Aforno/AgentNotch/releases/latest")
        )
    }
}
