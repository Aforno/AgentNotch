@testable import AgentsNotch
import AgentsNotchCore
import AppKit
import XCTest

final class ProviderIconAssetsTests: XCTestCase {
    @MainActor
    func testEveryKnownProviderLoadsItsArtworkFromPackageResources() throws {
        let providers: [(AgentProvider, Bool)] = [
            (.codex, false),
            (.claudeCode, false),
            (.grok, true),
            (.openCode, true),
            (.geminiCLI, false),
            (.antigravity, true),
            (.cursor, true),
        ]

        for (provider, isTemplate) in providers {
            let image = try XCTUnwrap(ProviderIconAssets.image(for: provider), provider.rawValue)
            XCTAssertTrue(image.isValid, provider.rawValue)
            XCTAssertEqual(image.isTemplate, isTemplate, provider.rawValue)
        }
    }
}
