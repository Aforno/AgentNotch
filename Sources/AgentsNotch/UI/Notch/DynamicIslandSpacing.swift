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

    /// Keeps the resting notch close to the sensor housing while leaving room
    /// for the status dot/count on the left. The provider deck stays inside the
    /// same fixed right ear regardless of how many providers are represented.
    static func compactEarWidth(for activeCount: Int) -> CGFloat {
        let digits = String(max(activeCount, 0)).count
        return 36 + CGFloat(max(digits - 1, 0)) * 7
    }
}
