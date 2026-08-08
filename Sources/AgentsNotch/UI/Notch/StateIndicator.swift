import AgentsNotchCore
import SwiftUI

struct StateIndicator: View {
    let state: AgentState
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(state.needsAttention ? 0.7 : 0), radius: 4)
            .accessibilityLabel(state.displayName)
    }

    private var color: Color {
        switch state {
        case .waitingForUser: .orange
        case .failed: .red
        case .completed: .green
        case .editing: .mint
        case .thinking: .purple
        case .starting: .cyan
        case .running, .executingTool: .blue
        case .idle: .secondary
        }
    }
}
