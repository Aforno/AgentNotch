import AgentsNotchCore
import SwiftUI

struct AgentListView: View {
    let sessions: [AgentSession]
    let topInset: CGFloat
    let onOpenSettings: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                HStack(spacing: DynamicIslandSpacing.related) {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 6, height: 6)
                    Text("No active agents")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: DynamicIslandSpacing.rowHeight)
            } else {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    Button {
                        onSelect(session.id)
                    } label: {
                        AgentRowView(session: session)
                    }
                    .buttonStyle(.plain)

                    if index < sessions.count - 1 {
                        Divider()
                            .overlay(.white.opacity(0.08))
                            .padding(.leading, 36)
                    }
                }
            }
        }
        .padding(.top, topInset)
        .padding(.bottom, DynamicIslandSpacing.expandedBottom)
        .overlay(alignment: .topTrailing) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, DynamicIslandSpacing.standard)
            .help("Settings")
            .accessibilityLabel("Open Settings")
        }
    }
}
