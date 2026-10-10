import AgentsNotchCore
import AppKit
import SwiftUI

/// A compact provider mark. Template assets follow the surrounding label color,
/// while color-dependent brand artwork keeps its original rendering.
/// Unknown integrations still get a neutral terminal glyph instead of an empty gap.
struct ProviderIconView: View {
    let provider: AgentProvider
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let image = ProviderIconAssets.image(for: provider) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(image.isTemplate ? .template : .original)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackSymbol: String {
        "terminal"
    }
}

private struct ProviderIconAsset: Hashable {
    let imageSet: String
    let file: String
    var isTemplate = true
}

@MainActor
enum ProviderIconAssets {
    private static let cache = NSCache<NSString, NSImage>()
    private static let bundle = Bundle.main.url(
        forResource: "AgentsNotch_AgentsNotch",
        withExtension: "bundle"
    ).flatMap { Bundle(url: $0) } ?? Bundle.module

    private static func asset(for provider: AgentProvider) -> ProviderIconAsset? {
        switch provider {
        case .codex: .init(imageSet: "ProviderCodex", file: "codex.svg", isTemplate: false)
        case .claudeCode: .init(imageSet: "ProviderClaudeCode", file: "clawd.svg", isTemplate: false)
        case .grok: .init(imageSet: "ProviderGrok", file: "grok.svg")
        case .openCode: .init(imageSet: "ProviderOpenCode", file: "opencode.svg")
        case .geminiCLI: .init(imageSet: "ProviderGemini", file: "gemini.svg", isTemplate: false)
        case .antigravity: .init(imageSet: "ProviderAntigravity", file: "antigravity.svg")
        case .cursor: .init(imageSet: "ProviderCursor", file: "cursor.svg")
        default: nil
        }
    }

    /// Resolve package resources in development and in the staged app bundle.
    static func image(for provider: AgentProvider) -> NSImage? {
        guard let asset = asset(for: provider) else { return nil }
        let cacheKey = "\(asset.imageSet)/\(asset.file)/\(asset.isTemplate)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let relativePath = "ProviderIcons.xcassets/\(asset.imageSet).imageset/\(asset.file)"
        // Xcode compiles catalogs; command-line SwiftPM copies the raw SVGs.
        let url = bundle.resourceURL?.appendingPathComponent(relativePath)
        let image = bundle.image(forResource: asset.imageSet)
            ?? url.flatMap { NSImage(contentsOf: $0) }
        guard let image else { return nil }
        image.isTemplate = asset.isTemplate
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}
