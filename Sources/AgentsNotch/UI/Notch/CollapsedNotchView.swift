import AgentsNotchCore
import SwiftUI

struct CollapsedNotchView: View {
    let sessions: [AgentSession]

    private var activeCount: Int { sessions.filter(\.isActive).count }
    private var attention: AgentSession? { sessions.first(where: \.needsAttention) }

    var body: some View {
        Color.clear
            .overlay(alignment: .leading) {
                leadingStatus
                    .padding(.leading, DynamicIslandSpacing.outer)
            }
            .overlay(alignment: .trailing) {
                if attention != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.trailing, DynamicIslandSpacing.outer)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
    }

    private var leadingStatus: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: attention?.state ?? .running, size: 7)
            Text("\(activeCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
        .fixedSize()
    }

    private var accessibilitySummary: String {
        if let attention { return "\(attention.provider.displayName) needs attention" }
        return activeCount == 0 ? "No active agents" : "\(activeCount) active agents"
    }
}
