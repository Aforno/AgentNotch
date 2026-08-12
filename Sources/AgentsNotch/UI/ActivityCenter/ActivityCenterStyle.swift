import AgentsNotchCore
import AppKit
import SwiftUI

/// Compact dark pill with hairline border — Settings, Setup, and other deep-black windows.
struct NotchPillButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchWindowFont.control)
            .foregroundStyle(
                destructive
                    ? Color.red.opacity(configuration.isPressed ? 0.7 : 0.88)
                    : Color.white.opacity(configuration.isPressed ? 0.62 : 0.82)
            )
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                configuration.isPressed
                    ? NotchWindowPalette.raisedPressed
                    : NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Square icon control matching `NotchPillButtonStyle` (refresh, etc.).
struct NotchIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.55 : 0.72))
            .frame(width: 26, height: 26)
            .background(
                configuration.isPressed
                    ? NotchWindowPalette.raisedPressed
                    : NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Static icon label for menu triggers that should match `NotchIconButtonStyle`.
struct NotchIconControlLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.72))
            .frame(width: 26, height: 26)
            .background(
                NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
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
