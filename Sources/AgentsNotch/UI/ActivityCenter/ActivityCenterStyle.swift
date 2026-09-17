import AgentsNotchCore
import AppKit
import SwiftUI

/// Rest, hover, and press fills shared by every deep-black window control.
enum NotchControlFill {
    static let rest = NotchWindowPalette.raisedStrong
    static let hover = NotchWindowPalette.raisedPressed
    static let pressed = NotchWindowPalette.raisedActive
    static let border = Color.white.opacity(0.08)
    static let hoverBorder = Color.white.opacity(0.16)
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
struct NotchPillButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
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
                        ? Color.red.opacity(configuration.isPressed ? 0.7 : 0.88)
                        : Color.white.opacity(configuration.isPressed ? 0.62 : 0.82)
                )
                .padding(.horizontal, 11)
                .frame(height: 26)
                .notchControlSurface(fill: fill)
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
                .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.55 : 0.72))
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
            .foregroundStyle(Color.white.opacity(isHovering ? 0.9 : 0.72))
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
                .foregroundStyle(.white.opacity(0.74))
            if let trailing {
                Text(trailing)
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
