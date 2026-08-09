import AgentsNotchCore
import SwiftUI

struct ActivityMetric: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Rectangle()
                .fill(value > 0 ? color : NotchWindowPalette.tertiaryText)
                .frame(width: 3, height: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                Text("\(value)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
            }
        }
        .frame(minWidth: 70, alignment: .leading)
    }
}

struct ActivitySessionRow: View {
    let session: AgentSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(activityColor(for: session.state))
                .frame(width: 3)

            ProviderIconView(provider: session.provider, size: 18)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.provider.displayName.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                    Text(session.updatedAt, style: .relative)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                }

                Text(session.task)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(rowDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 3)
            StateIndicator(state: session.state, size: 9)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? NotchWindowPalette.raisedStrong : NotchWindowPalette.raised)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSelected ? NotchWindowPalette.strongBorder : NotchWindowPalette.border,
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var rowDetail: String {
        let project = session.workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent }
        return [project, session.currentActivity].compactMap { $0 }.joined(separator: " / ")
    }
}

