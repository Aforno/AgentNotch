import AgentsNotchCore
import AppKit
import SwiftUI

/// Rest, hover, and press fills shared by every deep-black window control.
enum NotchControlFill {
    static let rest = NotchWindowPalette.raisedStrong
    static let hover = NotchWindowPalette.raisedPressed
    static let pressed = NotchWindowPalette.raisedActive
    static let border = NotchWindowPalette.border
    static let hoverBorder = NotchWindowPalette.borderStrong
    static let radius: CGFloat = 7
}

extension View {
    /// Fill plus hairline border for the deep-black window control vocabulary.
    /// The border brightens off the rest fill so hover reads without motion.
    func notchControlSurface(fill: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchControlFill.radius, style: .continuous)
        return background(fill, in: shape)
            .overlay(
                shape.strokeBorder(
                    fill == NotchControlFill.rest
                        ? NotchControlFill.border
                        : NotchControlFill.hoverBorder,
                    lineWidth: 1
                )
            )
    }
}

/// Compact dark pill with hairline border — Settings, Setup, and other deep-black windows.
/// `prominent` fills it with the brand hue for the one default action per window.
struct NotchPillButtonStyle: ButtonStyle {
    var destructive: Bool = false
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            NotchHoverSurface(
                isPressed: configuration.isPressed,
                rest: NotchWindowPalette.active.opacity(NotchAccentContrast.primaryFillOpacity),
                hover: NotchWindowPalette.active,
                pressed: NotchWindowPalette.active.opacity(0.72)
            ) { fill in
                configuration.label
                    .font(NotchWindowFont.control)
                    .foregroundStyle(NotchAccentContrast.foreground(for: NotchBrand.active))
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(fill, in: RoundedRectangle(cornerRadius: NotchControlFill.radius, style: .continuous))
            }
        } else {
            NotchHoverSurface(
                isPressed: configuration.isPressed,
                rest: NotchControlFill.rest,
                hover: NotchControlFill.hover,
                pressed: NotchControlFill.pressed
            ) { fill in
                configuration.label
                    .font(NotchWindowFont.control)
                    .foregroundStyle(
                        destructive
                            ? NotchWindowPalette.failure.opacity(configuration.isPressed ? 0.7 : 0.9)
                            : configuration.isPressed ? NotchWindowPalette.secondaryText : NotchWindowPalette.primaryText
                    )
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .notchControlSurface(fill: fill)
            }
        }
    }
}

/// Square icon control matching `NotchPillButtonStyle` (refresh, etc.).
struct NotchIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NotchHoverSurface(
            isPressed: configuration.isPressed,
            rest: NotchControlFill.rest,
            hover: NotchControlFill.hover,
            pressed: NotchControlFill.pressed
        ) { fill in
            configuration.label
                .font(NotchWindowFont.control)
                .foregroundStyle(configuration.isPressed ? NotchWindowPalette.tertiaryText : NotchWindowPalette.secondaryText)
                .frame(width: 26, height: 26)
                .notchControlSurface(fill: fill)
        }
    }
}

/// Static icon label for menu triggers that should match `NotchIconButtonStyle`.
/// `Menu` owns its own press handling, so hover is all this can add.
struct NotchIconControlLabel: View {
    let systemName: String

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemName)
            .font(NotchWindowFont.control)
            .foregroundStyle(isHovering ? NotchWindowPalette.primaryText : NotchWindowPalette.secondaryText)
            .frame(width: 26, height: 26)
            .notchControlSurface(fill: isHovering ? NotchControlFill.hover : NotchControlFill.rest)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}

/// Section label used across Activity Center and Settings: sentence case,
/// semibold, muted — no uppercase, no monospace, no `.black` weight.
struct NotchSectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(NotchWindowFont.sectionLabel)
                .foregroundStyle(NotchWindowPalette.secondaryText)
            if let trailing {
                Text(trailing)
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
