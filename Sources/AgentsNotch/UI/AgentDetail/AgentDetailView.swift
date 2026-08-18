import AgentsNotchCore
import SwiftUI

struct AgentDetailView: View {
    let session: AgentSession
    let parent: AgentSession?
    let children: [AgentSession]
    let onBack: () -> Void
    let onSelectSession: (String) -> Void
    let onOpen: () -> Void
    let outerCornerRadius: CGFloat
    let onIdealHeightChange: (CGFloat) -> Void
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: DynamicIslandSpacing.standard) {
            HStack(spacing: DynamicIslandSpacing.related) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back")
                .accessibilityLabel("Back")

                StateIndicator(state: session.state, size: 8)
                ProviderIconView(provider: session.provider, size: 15)
                    .foregroundStyle(.white.opacity(0.9))
                Text(session.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if session.isSubagent {
                    Text(session.agentRole?
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: ":", with: " ")
                        .capitalized ?? "Subagent")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                Spacer()
                Text(session.state.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(session.needsAttention ? .orange : .white.opacity(0.42))
            }
            .padding(.horizontal, DynamicIslandSpacing.outer)

            ScrollView {
                VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                    VStack(alignment: .leading, spacing: DynamicIslandSpacing.tight) {
                        Text(privacyModeEnabled ? "Private activity" : session.task)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(privacyModeEnabled ? session.state.displayName : session.currentActivity)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }

                    if let directory = session.workingDirectory {
                        Label(URL(fileURLWithPath: directory).lastPathComponent, systemImage: "folder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }

                    if privacyModeEnabled {
                        Label("Activity details are hidden by Privacy mode", systemImage: "eye.slash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    } else {
                        AgentRelationshipsView(
                            parent: parent,
                            children: children,
                            onSelect: onSelectSession
                        )

                        if let plan = session.plan {
                            AgentPlanProgressView(plan: plan)
                        }

                        if !session.workflows.isEmpty {
                            AgentWorkflowsView(workflows: session.workflows)
                        }

                        if !session.recentFiles.isEmpty {
                            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                                ForEach(session.recentFiles.prefix(3), id: \.self) { file in
                                    HStack(spacing: DynamicIslandSpacing.related) {
                                        Image(systemName: "doc")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white.opacity(0.3))
                                        Text(URL(fileURLWithPath: file).lastPathComponent)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.white.opacity(0.58))
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                            ForEach(session.recentEvents.prefix(4)) { event in
                                HStack(alignment: .firstTextBaseline, spacing: DynamicIslandSpacing.related) {
                                    Text(event.timestamp, style: .time)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.25))
                                        .frame(width: 50, alignment: .leading)
                                    Text(event.activity ?? event.resolvedState.displayName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DynamicIslandSpacing.outer)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { contentGeometry in
                        Color.clear.preference(
                            key: AgentDetailContentHeightKey.self,
                            value: contentGeometry.size.height
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)

            if session.applicationURL != nil || session.workingDirectory != nil {
                Button(action: onOpen) {
                    HStack(spacing: DynamicIslandSpacing.related) {
                        Image(systemName: "arrow.up.forward.app")
                        Text(session.applicationURL == nil ? "Reveal repository" : "Open session")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(
                        .white.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: DynamicIslandSpacing.insetCornerRadius(
                                outerRadius: outerCornerRadius
                            ),
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DynamicIslandSpacing.outer)
                .accessibilityLabel(session.applicationURL == nil ? "Reveal repository" : "Open session")
            }
        }
        .padding(.bottom, DynamicIslandSpacing.outer)
        .onPreferenceChange(AgentDetailContentHeightKey.self) { contentHeight in
            guard contentHeight > 0 else { return }
            let fixedChromeHeight: CGFloat = session.applicationURL != nil
                || session.workingDirectory != nil ? 98 : 56
            onIdealHeightChange(contentHeight + fixedChromeHeight)
        }
    }
}

private struct AgentDetailContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
