import SwiftUI

/// Content-driven sizing and scroll affordances shared by the notch surfaces.
///
/// The notch sizes its window to its content, so content has to measure itself.
/// Those scroll regions also hide their indicators, which would leave a clipped
/// edge as the only hint that more exists — so they fade the edge instead.

private struct HeightReader: View {
    let onChange: @MainActor (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            Color.clear
                .onAppear { onChange(height) }
                .onChange(of: height) { _, value in onChange(value) }
        }
    }
}

/// Coordinate space linking `notchScrollContent` to its enclosing fade.
private enum NotchScrollSpace {
    static let name = "notchScroll"
}

private struct NotchScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    /// Content origin within the viewport: 0 at rest, negative once scrolled.
    var minY: CGFloat = 0
}

private struct NotchScrollMetricsKey: PreferenceKey {
    static let defaultValue = NotchScrollMetrics()

    static func reduce(value: inout NotchScrollMetrics, nextValue: () -> NotchScrollMetrics) {
        let next = nextValue()
        if next.contentHeight > 0 { value = next }
    }
}

extension View {
    /// Reports this view's laid-out height whenever it changes.
    func onHeightChange(_ action: @MainActor @escaping (CGFloat) -> Void) -> some View {
        background(HeightReader(onChange: action))
    }

    /// Marks the scrollable content so the enclosing `notchScrollEdgeFade` can
    /// tell whether anything remains below the fold.
    func notchScrollContent() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: NotchScrollMetricsKey.self,
                    value: NotchScrollMetrics(
                        contentHeight: geometry.size.height,
                        minY: geometry.frame(in: .named(NotchScrollSpace.name)).minY
                    )
                )
            }
        }
    }

    /// Applied to a `ScrollView` whose indicators are hidden: fades the bottom
    /// edge while more content remains below.
    func notchScrollEdgeFade() -> some View {
        modifier(NotchScrollEdgeFade())
    }
}

private struct NotchScrollEdgeFade: ViewModifier {
    @State private var metrics = NotchScrollMetrics()
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: NotchScrollSpace.name)
            .onPreferenceChange(NotchScrollMetricsKey.self) { value in
                MainActor.assumeIsolated { metrics = value }
            }
            .onHeightChange { viewportHeight = $0 }
            .mask(mask)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFaded)
    }

    private var isFaded: Bool {
        guard viewportHeight > 0, metrics.contentHeight > viewportHeight + 1 else { return false }
        return metrics.contentHeight + metrics.minY - viewportHeight > 4
    }

    private var mask: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: isFaded ? 0.9 : 1),
                .init(color: isFaded ? .clear : .black, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
