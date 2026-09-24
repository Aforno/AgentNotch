import AgentsNotchCore
import SwiftUI

/// The brief "Claude finished · repo" pill `NotchRootView` shows when a
/// top-level agent completes or fails, before the notch collapses again.
struct FinishedFlashView: View {
    let session: AgentSession

    private var failed: Bool { session.state == .failed }

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(NotchWindowFont.bodyEmphasis)
                .foregroundStyle(failed ? NotchWindowPalette.failure : NotchWindowPalette.success)

            ProviderIconView(provider: session.provider, size: 14)
                .foregroundStyle(NotchWindowPalette.primaryText)

            HStack(spacing: DynamicIslandSpacing.tight) {
                Text("\(session.provider.displayName) \(failed ? "failed" : "finished")")
                    .font(NotchWindowFont.captionEmphasis)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                if let project = session.projectName {
                    Text("·")
                        .foregroundStyle(NotchWindowPalette.quaternaryText)
                    Text(project)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(NotchWindowFont.footnoteEmphasis)
                .foregroundStyle(NotchWindowPalette.tertiaryText)
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let verb = failed ? "failed" : "finished"
        guard let project = session.projectName else { return "\(session.provider.displayName) \(verb)" }
        return "\(session.provider.displayName) \(verb) in \(project)"
    }
}
