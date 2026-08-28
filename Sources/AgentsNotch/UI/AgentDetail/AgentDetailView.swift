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
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false
    @State private var measuredContentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DynamicIslandSpacing.standard) {
            header
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
                    session.needsAttention ? .orange : NotchWindowPalette.tertiaryText
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

                if let directory = session.workingDirectory {
                    Label(URL(fileURLWithPath: directory).lastPathComponent, systemImage: "folder")
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
            .background {
                GeometryReader { contentGeometry in
                    let contentHeight = contentGeometry.size.height
                    Color.clear
                        .onAppear {
                            reportIdealHeight(contentHeight)
                        }
                        // Recreate the probe when measured height or chrome
                        // changes so `onAppear` re-runs on MainActor. Swift 6.0
                        // treats `onPreferenceChange` as `@Sendable`.
                        .id(AgentDetailHeightSignal(
                            contentHeight: contentHeight,
                            originActionCount: originDestinations.count
                        ))
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { viewport in
                Color.clear
                    .onAppear { viewportHeight = viewport.size.height }
                    .onChange(of: viewport.size.height) { _, height in
                        viewportHeight = height
                    }
            }
        }
        // Scroll indicators are hidden, so a clipped edge would otherwise be
        // the only hint that more content exists. Fade it instead.
        .mask(scrollEdgeMask)
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
        }
    }

    private var isScrollable: Bool {
        viewportHeight > 0 && measuredContentHeight > viewportHeight + 1
    }

    private var scrollEdgeMask: LinearGradient {
        let fadeStart: CGFloat = isScrollable ? 0.9 : 1
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: fadeStart),
                .init(color: isScrollable ? .clear : .black, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var originDestinations: [OriginOpenDestination] {
        OriginActivationService.destinations(for: session)
    }

    private func reportIdealHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0 else { return }
        measuredContentHeight = contentHeight
        let fixedChromeHeight: CGFloat = originDestinations.isEmpty ? 56 : 98
        onIdealHeightChange(contentHeight + fixedChromeHeight)
    }
}

private struct AgentDetailHeightSignal: Hashable {
    var contentHeight: CGFloat
    var originActionCount: Int
}
