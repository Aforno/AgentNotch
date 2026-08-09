import AgentsNotchCore
import SwiftUI

struct AgentListView: View {
    let sessions: [AgentSession]
    let relatedSessions: [AgentSession]
    let topInset: CGFloat
    let onOpenSettings: () -> Void
    let onSelect: (String) -> Void

    static func rowsHeight(for sessions: [AgentSession], relatedSessions _: [AgentSession]) -> CGFloat {
        CGFloat(sessions.count) * DynamicIslandSpacing.rowHeight
    }

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
                        AgentRowView(
                            session: session,
                            subagents: descendantSessions(of: session)
                        )
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

    static func descendantSessions(of session: AgentSession, in sessions: [AgentSession]) -> [AgentSession] {
        var result: [AgentSession] = []
        var pending = [session.id]
        var visited: Set<String> = [session.id]

        while let parentID = pending.popLast() {
            for candidate in sessions
                where candidate.parentSessionId == parentID
                    && visited.insert(candidate.id).inserted
            {
                result.append(candidate)
                pending.append(candidate.id)
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.id < rhs.id
        }
    }

    private func descendantSessions(of session: AgentSession) -> [AgentSession] {
        Self.descendantSessions(of: session, in: relatedSessions)
    }
}
