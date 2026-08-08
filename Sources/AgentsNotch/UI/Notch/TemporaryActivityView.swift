import AgentsNotchCore
import SwiftUI

struct TemporaryActivityView: View {
    let event: AgentEvent

    var body: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: event.resolvedState, size: 8)

            ProviderIconView(provider: event.provider, size: 14)
                .foregroundStyle(.white.opacity(0.9))

            Text(event.provider.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Text("·")
                .foregroundStyle(.white.opacity(0.32))

            Text(event.activity ?? event.resolvedState.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)

            Spacer(minLength: 0)

            if event.resolvedState == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
            } else if event.resolvedState.needsAttention {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
    }
}
