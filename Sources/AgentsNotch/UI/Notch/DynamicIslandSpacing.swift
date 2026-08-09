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
    static let compactInset: CGFloat = 8

    /// Keeps the resting notch close to the sensor housing while leaving room
    /// for the status dot and count. Extra width is added only when the count
    /// gains another digit instead of reserving a three-digit ear at all times.
    static func compactEarWidth(for activeCount: Int) -> CGFloat {
        let digits = String(max(activeCount, 0)).count
        return 36 + CGFloat(max(digits - 1, 0)) * 7
    }
}
