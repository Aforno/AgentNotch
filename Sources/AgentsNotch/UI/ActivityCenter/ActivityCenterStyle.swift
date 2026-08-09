import AgentsNotchCore
import SwiftUI

/// Quiet, borderless control that matches the notch's primary action button
/// (`AgentDetailView`): 11pt semibold on a soft white fill, radius 8.
struct ActivityActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchWindowFont.control.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                configuration.isPressed
                    ? NotchWindowPalette.raisedPressed
                    : NotchWindowPalette.raisedStrong,
                in: RoundedRectangle(cornerRadius: NotchWindowMetrics.controlRadius, style: .continuous)
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
