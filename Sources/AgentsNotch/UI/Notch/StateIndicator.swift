import AgentsNotchCore
import SwiftUI

struct StateIndicator: View {
    let state: AgentState
    var size: CGFloat = 12

    var body: some View {
        Group {
            if state.showsSpinner {
                StateSpinner(color: color, size: size)
            } else {
                Image(systemName: state.systemImage)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(color)
            }
        }
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

private struct StateSpinner: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Circle()
                .trim(from: 0.12, to: 0.82)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: max(1.25, size * 0.16),
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(rotation(at: context.date)))
        }
        .accessibilityHidden(true)
    }

    private func rotation(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
    }
}

private extension AgentState {
    var showsSpinner: Bool {
        switch self {
        case .starting, .running, .executingTool: true
        case .idle, .thinking, .editing, .waitingForUser, .completed, .failed: false
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "minus"
        case .thinking: "ellipsis"
        case .editing: "pencil"
        case .waitingForUser: "questionmark"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .starting, .running, .executingTool: ""
        }
    }
}
