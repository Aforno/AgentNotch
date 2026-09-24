import AgentsNotchCore
import SwiftUI

struct ActivityMetric: View {
    let title: String
    let value: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(value > 0 ? color : NotchWindowPalette.quaternaryText)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                Text(title)
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(isSelected ? NotchWindowPalette.primaryText : NotchWindowPalette.secondaryText)

                Text("\(value)")
                    .font(NotchWindowFont.counter)
                    .foregroundStyle(value > 0 ? NotchWindowPalette.primaryText : NotchWindowPalette.tertiaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                isSelected ? color.opacity(0.2) : NotchWindowPalette.raised,
                in: Capsule()
            )
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(color.opacity(0.42), lineWidth: 0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Show all sessions" : "Show \(title.lowercased()) sessions")
        .accessibilityLabel("\(title), \(value) sessions")
        .accessibilityHint(isSelected ? "Show all sessions" : "Filter sessions")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ActivitySessionRow: View {
    let session: AgentSession
    let isSelected: Bool

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ProviderIconView(provider: session.provider, size: 18)
                .frame(width: 22)

            // The provider icon already names the provider, so the second line
            // carries only what distinguishes this session.
            VStack(alignment: .leading, spacing: 2) {
                Text(session.task)
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                    .lineLimit(1)

                Text(rowDetail)
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                StateIndicator(state: session.state, size: 9)
                ElapsedLabel(since: session.updatedAt)
            }
            .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            rowFill,
            in: RoundedRectangle(cornerRadius: NotchWindowMetrics.cardRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: NotchWindowMetrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }

    private var rowFill: Color {
        if isSelected { return NotchWindowPalette.raisedStrong }
        return isHovering ? NotchWindowPalette.raised : .clear
    }

    private var rowDetail: String {
        let project = session.projectName
        return [project, session.currentActivity].compactMap { $0 }.joined(separator: " · ")
    }
}
