import AgentsNotchCore
import SwiftUI

struct TemporaryActivityView: View {
    let session: AgentSession
    let waitingCount: Int
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: session.state, size: 8)

            ProviderIconView(provider: session.provider, size: 14)
                .foregroundStyle(NotchWindowPalette.primaryText)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DynamicIslandSpacing.tight) {
                    Text(session.provider.displayName)
                        .font(NotchWindowFont.captionEmphasis)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                    Text("·")
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.quaternaryText)
                    Text(projectName)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
                .lineLimit(1)

                Text(privacyModeEnabled ? session.state.displayName : session.currentActivity)
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if waitingCount > 1 {
                Text("\(waitingCount) waiting")
                    .font(NotchWindowFont.footnoteEmphasis)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(NotchWindowFont.footnoteEmphasis)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
    }

    private var projectName: String {
        guard let project = session.projectName else {
            return privacyModeEnabled ? session.provider.displayName : session.task
        }
        return project
    }
}
