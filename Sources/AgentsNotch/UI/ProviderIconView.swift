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
            if let asset = iconAsset, let image = ProviderIconAssets.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(asset.isTemplate ? .template : .original)
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

    private var iconAsset: ProviderIconAsset? {
        switch provider {
        case .codex: .init(imageSet: "ProviderCodex", file: "codex.svg", isTemplate: false)
        case .claudeCode: .init(imageSet: "ProviderClaudeCode", file: "clawd.svg", isTemplate: false)
        case .grok: .init(imageSet: "ProviderGrok", file: "grok.svg")
        case .openCode: .init(imageSet: "ProviderOpenCode", file: "opencode.svg")
        case .geminiCLI: .init(imageSet: "ProviderGemini", file: "gemini.svg", isTemplate: false)
        case .cursor: .init(imageSet: "ProviderCursor", file: "cursor.svg")
        default: nil
        }
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
private enum ProviderIconAssets {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for asset: ProviderIconAsset) -> NSImage? {
        let cacheKey = "\(asset.imageSet)/\(asset.file)/\(asset.isTemplate)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let relativePath = "ProviderIcons.xcassets/\(asset.imageSet).imageset/\(asset.file)"
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(relativePath),
            Bundle.main.bundleURL
                .appendingPathComponent("AgentsNotch_AgentsNotch.bundle")
                .appendingPathComponent(relativePath),
        ]

        for case let url? in candidates {
            guard let image = NSImage(contentsOf: url) else { continue }
            image.isTemplate = asset.isTemplate
            cache.setObject(image, forKey: cacheKey)
            return image
        }
        return nil
    }
}
