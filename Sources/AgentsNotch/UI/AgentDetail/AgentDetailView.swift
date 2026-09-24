import AgentsNotchCore
import SwiftUI

struct AgentDetailView: View {
    let session: AgentSession
    let parent: AgentSession?
    let children: [AgentSession]
    let onBack: () -> Void
    let onSelectSession: (String) -> Void
    let onOpen: (OriginOpenAction) -> Void
    let canAnswer: Bool
    let onAnswer: (AgentReplyDecision, String?, [String: [String]]?) -> Void
    let outerCornerRadius: CGFloat
    let onIdealHeightChange: (CGFloat) -> Void
    @AppStorage(AppPreferences.Key.privacyModeEnabled) private var privacyModeEnabled = false
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var actionsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DynamicIslandSpacing.standard) {
            header
                .onHeightChange { height in
                    headerHeight = height
                    reportIdealHeight()
                }
            scrollingContent
            originActions
        }
        .padding(.bottom, DynamicIslandSpacing.outer)
    }

    private var header: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }
            .buttonStyle(NotchGlyphButtonStyle())
            .help("Back")
            .accessibilityLabel("Back")

            StateIndicator(state: session.state, size: 8)
            ProviderIconView(provider: session.provider, size: 15)
                .foregroundStyle(NotchWindowPalette.primaryText)
            Text(session.provider.displayName)
                .font(NotchWindowFont.subtitle)
                .foregroundStyle(NotchWindowPalette.primaryText)
            if session.isSubagent {
                Text(AgentRowPresentation.formattedRole(session.agentRole))
                    .font(NotchWindowFont.footnoteEmphasis)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(NotchWindowPalette.raisedStrong, in: Capsule())
            }
            Spacer()
            Text(session.state.displayName)
                .font(NotchWindowFont.footnoteEmphasis)
                .foregroundStyle(
                    session.needsAttention ? NotchWindowPalette.attention : NotchWindowPalette.tertiaryText
                )
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
    }

    private var scrollingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.standard) {
                VStack(alignment: .leading, spacing: DynamicIslandSpacing.tight) {
                    Text(privacyModeEnabled ? "Private activity" : session.task)
                        .font(NotchWindowFont.title)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                        .lineLimit(2)
                    Text(privacyModeEnabled ? session.state.displayName : session.currentActivity)
                        .font(NotchWindowFont.body)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                        .lineLimit(2)
                }

                if let project = session.projectName {
                    Label(project, systemImage: "folder")
                        .font(NotchWindowFont.control)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                        .lineLimit(1)
                }

                if privacyModeEnabled {
                    Label("Activity details are hidden by Privacy mode", systemImage: "eye.slash")
                        .font(NotchWindowFont.control)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
                } else {
                    if canAnswer, let pending = session.pendingReply {
                        WaitingReplyActions(pending: pending, onAnswer: onAnswer)
                            .id(pending.replyId)
                    }
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

                    recentFiles
                    recentEvents
                }
            }
            .padding(.horizontal, DynamicIslandSpacing.outer)
            .frame(maxWidth: .infinity, alignment: .leading)
            .notchScrollContent()
            .onHeightChange { height in
                contentHeight = height
                reportIdealHeight()
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchScrollEdgeFade()
    }

    @ViewBuilder
    private var recentFiles: some View {
        if !session.recentFiles.isEmpty {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                NotchSectionLabel(title: "Recent files")
                ForEach(session.recentFiles.prefix(3), id: \.self) { file in
                    HStack(spacing: DynamicIslandSpacing.related) {
                        Image(systemName: "doc")
                            .font(NotchWindowFont.footnote)
                            .foregroundStyle(NotchWindowPalette.quaternaryText)
                        Text(URL(fileURLWithPath: file).lastPathComponent)
                            .font(NotchWindowFont.monoCaption)
                            .foregroundStyle(NotchWindowPalette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentEvents: some View {
        if !session.recentEvents.isEmpty {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                NotchSectionLabel(title: "Recent activity")
                ForEach(session.recentEvents.prefix(4)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: DynamicIslandSpacing.related) {
                        Text(event.timestamp, style: .time)
                            .font(NotchWindowFont.mono)
                            .foregroundStyle(NotchWindowPalette.quaternaryText)
                            .frame(width: 54, alignment: .leading)
                        Text(event.activity ?? event.resolvedState.displayName)
                            .font(NotchWindowFont.footnote)
                            .foregroundStyle(NotchWindowPalette.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var originActions: some View {
        if !originDestinations.isEmpty {
            HStack(spacing: DynamicIslandSpacing.related) {
                ForEach(originDestinations, id: \.action) { destination in
                    Button {
                        onOpen(destination.action)
                    } label: {
                        HStack(spacing: DynamicIslandSpacing.related) {
                            Image(systemName: destination.systemImage)
                            Text(destination.title)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(NotchActionButtonStyle(
                        emphasis: .neutral,
                        cornerRadius: DynamicIslandSpacing.insetCornerRadius(
                            outerRadius: outerCornerRadius
                        ),
                        expands: true
                    ))
                    .accessibilityLabel(destination.title)
                }
            }
            .padding(.horizontal, DynamicIslandSpacing.outer)
            .onHeightChange { height in
                actionsHeight = height
                reportIdealHeight()
            }
        }
    }

    private var originDestinations: [OriginOpenDestination] {
        OriginActivationService.destinations(for: session)
    }

    /// Chrome is the header, the origin actions when present, and the fixed
    /// gaps the body puts between them. Measured rather than assumed, so a
    /// header that wraps cannot leave the pane mis-sized.
    private func reportIdealHeight() {
        guard headerHeight > 0, contentHeight > 0 else { return }
        let hasActions = !originDestinations.isEmpty
        let gapCount: CGFloat = hasActions ? 2 : 1
        onIdealHeightChange(
            headerHeight
                + contentHeight
                + (hasActions ? actionsHeight : 0)
                + DynamicIslandSpacing.standard * gapCount
                + DynamicIslandSpacing.outer
        )
    }
}
