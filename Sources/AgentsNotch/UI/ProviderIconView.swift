import AgentsNotchCore
import AppKit
import SwiftUI

/// A compact, monochrome provider mark that follows the surrounding label color.
/// Unknown integrations still get a neutral terminal glyph instead of an empty gap.
struct ProviderIconView: View {
    let provider: AgentProvider
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let asset = iconAsset, let image = ProviderIconAssets.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: "terminal")
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
        case .codex: .init(imageSet: "ProviderCodex", file: "codex.svg")
        case .claudeCode: .init(imageSet: "ProviderClaudeCode", file: "claude-code.svg")
        case .grok: .init(imageSet: "ProviderGrok", file: "grok.svg")
        case .openCode: .init(imageSet: "ProviderOpenCode", file: "opencode.svg")
        case .geminiCLI: .init(imageSet: "ProviderGemini", file: "gemini.svg")
        case .cursor: .init(imageSet: "ProviderCursor", file: "cursor.svg")
        default: nil
        }
    }
}

private struct ProviderIconAsset: Hashable {
    let imageSet: String
    let file: String
}

private enum ProviderIconAssets {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for asset: ProviderIconAsset) -> NSImage? {
        let cacheKey = "\(asset.imageSet)/\(asset.file)" as NSString
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
            image.isTemplate = true
            cache.setObject(image, forKey: cacheKey)
            return image
        }
        return nil
    }
}
