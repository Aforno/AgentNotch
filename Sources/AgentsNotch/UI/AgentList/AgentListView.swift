import AgentsNotchCore
import SwiftUI

struct AgentListView: View {
    let sessions: [AgentSession]
    let relatedSessions: [AgentSession]
    var hiddenGroupCount: Int = 0
    /// Shown by the empty state so the list still answers "what just happened?".
    var lastFinishedSession: AgentSession?
    let topInset: CGFloat
    let menuBarHeight: CGFloat
    let onOpenSettings: () -> Void
    let onOpenActivityCenter: () -> Void
    let onSelect: (String) -> Void
    @AppStorage(AppPreferences.Key.privacyModeEnabled) private var privacyModeEnabled = false

    static func rowsHeight(for sessions: [AgentSession], hiddenGroupCount: Int = 0) -> CGFloat {
        if sessions.isEmpty {
            return DynamicIslandSpacing.rowHeight
        }
        let sessionRows = CGFloat(sessions.count) * DynamicIslandSpacing.rowHeight
        let overflowRow: CGFloat = hiddenGroupCount > 0 ? DynamicIslandSpacing.overflowRowHeight : 0
        return sessionRows + overflowRow
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
                    .buttonStyle(NotchRowButtonStyle())

                    if index < sessions.count - 1 || hiddenGroupCount > 0 {
                        Divider()
                            .overlay(NotchWindowPalette.hairline)
                            .padding(.horizontal, 42)
                    }
                }

                if hiddenGroupCount > 0 {
                    Button(action: onOpenActivityCenter) {
                        HStack(spacing: DynamicIslandSpacing.tight) {
                            Spacer()
                            Text("+\(hiddenGroupCount) more in Activity Center")
                                .font(NotchWindowFont.footnoteEmphasis)
                                .foregroundStyle(NotchWindowPalette.tertiaryText)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(NotchWindowPalette.quaternaryText)
                            Spacer()
                        }
                        .frame(height: DynamicIslandSpacing.overflowRowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchRowButtonStyle())
                    .accessibilityLabel("\(hiddenGroupCount) more active agents in Activity Center")
                }
            }
        }
    }

    private var chromeRow: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            if sessions.isEmpty {
                emptyState
            }

            Spacer(minLength: 0)

            HStack(spacing: DynamicIslandSpacing.related) {
                Button(action: onOpenActivityCenter) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(NotchWindowFont.control)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
                .buttonStyle(NotchGlyphButtonStyle())
                .help("Activity Center")
                .accessibilityLabel("Open Activity Center")

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(NotchWindowFont.control)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
                .buttonStyle(NotchGlyphButtonStyle())
                .help("Settings")
                .accessibilityLabel("Open Settings")
            }
            .offset(y: Self.controlsVerticalOffset(
                topInset: topInset,
                menuBarHeight: menuBarHeight
            ))
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .frame(
            height: sessions.isEmpty
                ? DynamicIslandSpacing.rowHeight
                : DynamicIslandSpacing.chromeHeight
        )
    }

    /// State on the left, the action it offers on the right. Without the
    /// separator the two labels ran together as one sentence.
    private var emptyState: some View {
        Button(action: onOpenActivityCenter) {
            HStack(spacing: DynamicIslandSpacing.related) {
                Circle()
                    .fill(NotchWindowPalette.quaternaryText)
                    .frame(width: 6, height: 6)
                Text(emptyTitle)
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                    .lineLimit(1)
                Text("·")
                    .font(NotchWindowFont.footnote)
                    .foregroundStyle(NotchWindowPalette.quaternaryText)
                HStack(spacing: DynamicIslandSpacing.tight) {
                    Text("Browse recent")
                        .font(NotchWindowFont.footnoteEmphasis)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(NotchWindowPalette.secondaryText)
            }
            .padding(.horizontal, 6)
            .frame(height: DynamicIslandSpacing.chromeHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchRowButtonStyle(inset: 0))
        .accessibilityLabel("\(emptyTitle). Open Activity Center to browse recent sessions.")
    }

    /// "Claude finished · repo · 2m ago", or the plain empty message.
    private var emptyTitle: String {
        guard let session = lastFinishedSession, !privacyModeEnabled else { return "No active agents" }
        let verb = session.state == .failed ? "failed" : "finished"
        let age = ElapsedLabel.format(Date().timeIntervalSince(session.completedAt ?? session.updatedAt))
        let when = age == "now" ? "just now" : "\(age) ago"
        let project = session.projectName.map { " · \($0)" } ?? ""
        return "\(session.provider.displayName) \(verb)\(project) · \(when)"
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
