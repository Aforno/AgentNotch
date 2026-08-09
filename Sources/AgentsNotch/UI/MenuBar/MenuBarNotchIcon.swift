import SwiftUI

struct MenuBarNotchIcon: View {
    let activeCount: Int
    let attentionCount: Int

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NotchShape(bottomRadius: 4)
                .fill(.primary)
                .frame(width: 19, height: 12)

            if attentionCount > 0 {
                statusDot(color: .orange)
            } else if activeCount > 0 {
                statusDot(color: .blue)
            }
        }
        .frame(width: 21, height: 14, alignment: .topLeading)
        .accessibilityLabel(accessibilityLabel)
    }

    private func statusDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .overlay {
                Circle().stroke(.black.opacity(0.75), lineWidth: 1)
            }
    }

    private var accessibilityLabel: String {
        if attentionCount > 0 {
            return "Agents Notch, \(attentionCount) need attention"
        }
        if activeCount > 0 {
            return "Agents Notch, \(activeCount) active"
        }
        return "Agents Notch, idle"
    }
}
