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
    // Wide enough for a status dot plus a three-digit count while preserving
    // a full outer inset and clearance from the physical notch.
    static let compactEarWidth: CGFloat = 64
}
