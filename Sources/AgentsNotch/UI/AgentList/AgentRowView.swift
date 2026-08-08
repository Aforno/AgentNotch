import AgentsNotchCore
import SwiftUI

struct AgentRowView: View {
    let session: AgentSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: DynamicIslandSpacing.standard) {
                if session.isSubagent {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 10)
                }

                StateIndicator(state: session.state, size: 8)

                ProviderIconView(provider: session.provider, size: 14)
                    .foregroundStyle(.white.opacity(0.9))

                Text(session.isSubagent ? subagentLabel : session.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: session.isSubagent ? 78 : 62, alignment: .leading)

                Text(session.currentActivity)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(1)

                Spacer(minLength: DynamicIslandSpacing.related)

                if session.needsAttention {
                    Image(systemName: session.state == .failed ? "xmark" : "exclamationmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(session.state == .failed ? .red : .orange)
                } else {
                    Text(elapsed(from: session.startedAt, to: context.date))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, DynamicIslandSpacing.outer)
            .frame(height: DynamicIslandSpacing.rowHeight)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var subagentLabel: String {
        session.agentRole?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Subagent"
    }

    private var accessibilityLabel: String {
        let identity = session.isSubagent
            ? "\(subagentLabel) subagent"
            : session.provider.displayName
        return "\(identity), \(session.currentActivity), \(session.state.displayName)"
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(Int(end.timeIntervalSince(start)), 0)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h"
    }
}
