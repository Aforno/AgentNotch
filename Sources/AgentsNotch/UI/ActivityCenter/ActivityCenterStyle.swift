import AgentsNotchCore
import SwiftUI

struct ActivityActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(configuration.isPressed ? NotchWindowPalette.raisedStrong : NotchWindowPalette.raised)
            .overlay {
                Rectangle().stroke(NotchWindowPalette.strongBorder, lineWidth: 1)
            }
    }
}

func activityColor(for state: AgentState) -> Color {
    switch state {
    case .idle: NotchWindowPalette.tertiaryText
    case .starting, .thinking, .running, .editing, .executingTool: .blue
    case .waitingForUser: .orange
    case .completed: .green
    case .failed: .red
    }
}
