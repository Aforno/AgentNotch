import AgentsNotchCore
import SwiftUI

struct TemporaryActivityView: View {
    let session: AgentSession
    let waitingCount: Int

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: session.state, size: 8)

            ProviderIconView(provider: session.provider, size: 14)
                .foregroundStyle(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DynamicIslandSpacing.tight) {
                    Text(session.provider.displayName)
                        .fontWeight(.semibold)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.32))
                    Text(projectName)
                        .foregroundStyle(.white.opacity(0.66))
                }
                .font(.system(size: 11))
                .lineLimit(1)

                Text(session.currentActivity)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if waitingCount > 1 {
                Text("\(waitingCount) waiting")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
    }

    private var projectName: String {
        guard let directory = session.workingDirectory else { return session.task }
        return URL(fileURLWithPath: directory).lastPathComponent
    }
}
