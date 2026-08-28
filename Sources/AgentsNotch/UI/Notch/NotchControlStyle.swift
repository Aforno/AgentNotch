import SwiftUI

/// Interactive vocabulary for the notch surface.
///
/// Hover and press fills distinguish controls from labels. Row highlight is
/// inset so content stays aligned with dividers and chrome.

/// Full-width list row: inset rounded highlight on hover, stronger on press.
///
/// The highlight is inset via the background layer rather than by padding the
/// label, so row content stays aligned with the dividers and the chrome above.
struct NotchRowButtonStyle: ButtonStyle {
    var inset: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        NotchHoverSurface(isPressed: configuration.isPressed) { fill in
            configuration.label
                .background {
                    RoundedRectangle(
                        cornerRadius: NotchWindowMetrics.cardRadius,
                        style: .continuous
                    )
                    .fill(fill)
                    .padding(.horizontal, inset)
                }
        }
    }
}

/// Square icon control used by the notch chrome (settings, activity, back).
struct NotchGlyphButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        NotchHoverSurface(isPressed: configuration.isPressed) { fill in
            configuration.label
                .frame(width: size, height: size)
                .background(
                    fill,
                    in: RoundedRectangle(
                        cornerRadius: NotchWindowMetrics.controlRadius,
                        style: .continuous
                    )
                )
                .contentShape(Rectangle())
        }
    }
}

/// Emphasis levels for the notch's committed actions (reply, open in app).
enum NotchActionEmphasis {
    /// The default action. Uses the system accent rather than orange so that
    /// orange keeps meaning "needs attention" and nothing else.
    case primary
    case neutral

    var fill: Color {
        switch self {
        case .primary: Color.accentColor.opacity(NotchAccentContrast.primaryFillOpacity)
        case .neutral: NotchWindowPalette.raisedStrong
        }
    }

    var hoverFill: Color {
        switch self {
        case .primary: Color.accentColor
        case .neutral: NotchWindowPalette.raisedPressed
        }
    }

    var pressedFill: Color {
        switch self {
        case .primary: Color.accentColor.opacity(0.72)
        case .neutral: NotchWindowPalette.raised
        }
    }

    var foreground: Color {
        switch self {
        case .primary: NotchAccentContrast.foreground(for: .controlAccentColor)
        case .neutral: NotchWindowPalette.primaryText
        }
    }
}

/// Capsule/rounded action button used for replies and origin destinations.
struct NotchActionButtonStyle: ButtonStyle {
    var emphasis: NotchActionEmphasis = .neutral
    var cornerRadius: CGFloat?
    var expands = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        NotchActionSurface(
            emphasis: emphasis,
            cornerRadius: cornerRadius,
            expands: expands,
            isEnabled: isEnabled,
            isPressed: configuration.isPressed,
            label: configuration.label
        )
    }
}

private struct NotchActionSurface<Label: View>: View {
    let emphasis: NotchActionEmphasis
    let cornerRadius: CGFloat?
    let expands: Bool
    let isEnabled: Bool
    let isPressed: Bool
    let label: Label

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        label
            .font(NotchWindowFont.bodyEmphasis)
            .foregroundStyle(emphasis.foreground.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, 12)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: 28)
            .background(fill, in: shape)
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
    }

    private var shape: AnyShape {
        guard let cornerRadius else { return AnyShape(Capsule()) }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fill: Color {
        guard isEnabled else { return NotchWindowPalette.raised }
        if isPressed { return emphasis.pressedFill }
        return isHovering ? emphasis.hoverFill : emphasis.fill
    }
}

/// Shared hover/press fill plumbing. `ButtonStyle` cannot observe hover on its
/// own, so the style body delegates to this stateful wrapper.
private struct NotchHoverSurface<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder let content: (Color) -> Content

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(fill)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
    }

    private var fill: Color {
        if isPressed { return NotchWindowPalette.raisedStrong }
        return isHovering ? NotchWindowPalette.hover : .clear
    }
}

/// Small keycap used to surface shortcuts that the notch already handles but
/// never advertised (Return to allow, Escape to deny, digits to pick options).
struct NotchKeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(NotchWindowFont.footnoteEmphasis)
            .foregroundStyle(NotchWindowPalette.primaryText)
            .frame(minWidth: 14)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(NotchWindowPalette.raisedPressed, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }
}
