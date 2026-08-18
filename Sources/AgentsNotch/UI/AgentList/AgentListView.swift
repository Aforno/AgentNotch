import AgentsNotchCore
import SwiftUI

struct AgentListView: View {
    let sessions: [AgentSession]
    let relatedSessions: [AgentSession]
    let topInset: CGFloat
    let menuBarHeight: CGFloat
    let onOpenSettings: () -> Void
    let onOpenActivityCenter: () -> Void
    let onSelect: (String) -> Void

    static func rowsHeight(for sessions: [AgentSession]) -> CGFloat {
        if sessions.isEmpty {
            return DynamicIslandSpacing.rowHeight
        }
        return CGFloat(sessions.count) * DynamicIslandSpacing.rowHeight
    }

    static func controlsVerticalOffset(topInset: CGFloat, menuBarHeight: CGFloat) -> CGFloat {
        menuBarHeight / 2 - topInset - DynamicIslandSpacing.chromeHeight / 2
    }

    var body: some View {
        ZStack(alignment: .top) {
            sessionRows
            chromeRow
        }
        .padding(.top, topInset)
        .padding(.bottom, DynamicIslandSpacing.expandedBottom)
    }

    @ViewBuilder
    private var sessionRows: some View {
        if sessions.isEmpty {
            Color.clear
                .frame(height: DynamicIslandSpacing.rowHeight)
        } else {
            VStack(spacing: 0) {
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
                            .padding(.horizontal, 42)
                    }
                }
            }
        }
    }

    private var chromeRow: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            if sessions.isEmpty {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 6, height: 6)
                Text("No active agents")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            HStack(spacing: DynamicIslandSpacing.related) {
                Button(action: onOpenActivityCenter) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help("Activity Center")
                .accessibilityLabel("Open Activity Center")

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .help("Settings")
                .accessibilityLabel("Open Settings")
            }
            .offset(y: Self.controlsVerticalOffset(
                topInset: topInset,
                menuBarHeight: menuBarHeight
            ))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .frame(
            height: sessions.isEmpty
                ? DynamicIslandSpacing.rowHeight
                : DynamicIslandSpacing.chromeHeight
        )
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
