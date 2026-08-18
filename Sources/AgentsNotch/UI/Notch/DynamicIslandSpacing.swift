import CoreGraphics

/// Spacing rhythm shared by every notch presentation. Values follow a 4-point
/// grid and keep content inset concentrically from the island's rounded edge.
enum DynamicIslandSpacing {
    static let tight: CGFloat = 4
    static let related: CGFloat = 8
    static let standard: CGFloat = 12
    static let outer: CGFloat = 16

    static let expandedTop: CGFloat = 8
    static let expandedBottom: CGFloat = 12
    static let rowHeight: CGFloat = 44
    /// Hover-list chrome for Activity Center and Settings, kept off session rows.
    static let chromeHeight: CGFloat = 28
    static let compactInset: CGFloat = 8
    static let compactProviderMarkSize: CGFloat = 18
    static let compactProviderStackWidth: CGFloat = 28
    static let compactProviderReveal: CGFloat = 5

    /// Keeps expanded presentations clear of the screen edge when a display
    /// is narrower than the preferred notch width.
    static let screenEdge: CGFloat = 16

    /// Derives an inset corner from the outer surface so nested controls near
    /// the rounded edge remain visually concentric.
    static func insetCornerRadius(outerRadius: CGFloat, inset: CGFloat = outer) -> CGFloat {
        max(tight, outerRadius - inset)
    }

    /// Keeps the resting notch close to the sensor housing while leaving room
    /// for the status dot/count on the left. The provider deck stays inside the
    /// same fixed right ear regardless of how many providers are represented.
    static func compactEarWidth(for activeCount: Int) -> CGFloat {
        let digits = String(max(activeCount, 0)).count
        return 36 + CGFloat(max(digits - 1, 0)) * 7
    }
}

/// Pure sizing rules for the notch presentations. Keeping these separate from
/// SwiftUI state makes display adaptation and content-driven height testable.
enum NotchLayoutMetrics {
    static let temporaryPreferredWidth: CGFloat = 392
    static let listPreferredWidth: CGFloat = 424
    static let detailPreferredWidth: CGFloat = 440
    static let maximumDetailContentHeight: CGFloat = 420
    static let minimumDetailContentHeight: CGFloat = 164

    static func expandedWidth(
        preferred: CGFloat,
        screenWidth: CGFloat,
        notchWidth: CGFloat
    ) -> CGFloat {
        let available = max(notchWidth, screenWidth - DynamicIslandSpacing.screenEdge * 2)
        return max(notchWidth, min(preferred, available))
    }

    static func detailContentHeight(
        measured: CGFloat,
        screenHeight: CGFloat,
        notchHeight: CGFloat
    ) -> CGFloat {
        let available = max(0, screenHeight - notchHeight - DynamicIslandSpacing.screenEdge)
        return min(
            max(measured, minimumDetailContentHeight),
            min(maximumDetailContentHeight, available)
        )
    }
}
