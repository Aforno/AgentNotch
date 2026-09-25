#if DEBUG
import AgentsNotchCore
import AppKit
import SwiftUI

/// Every notch presentation rendered side by side from static samples, so
/// visual drift is caught by looking rather than by waiting for live agents.
/// Opened from Settings → Debug. Nothing here touches the activity service.
struct DebugGalleryView: View {
    private let notchWidth: CGFloat = 185
    private let notchHeight: CGFloat = 32
    private let columns = [GridItem(.adaptive(minimum: galleryTileWidth), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "Notch Gallery",
                    detail: "Static samples of every presentation. Hover and click work; answers go nowhere."
                )
                section("Resting") { restingTiles }
                section("Moments") { momentTiles }
                section("Prompts") { promptTiles }
                section("Expanded") { expandedTiles }
            }
            .padding(NotchWindowMetrics.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 600, minHeight: 500)
        .deepBlackWindowSurface()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NotchSectionLabel(title: title)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                content()
            }
        }
    }

    // MARK: Tiles

    @ViewBuilder
    private var restingTiles: some View {
        GalleryTile(title: "Idle — hidden in the hardware notch", width: notchWidth, height: notchHeight, radius: 10) {
            Color.clear
        }
        collapsedTile("One agent running", state: .running, providers: [.codex])
        collapsedTile("Three agents, mixed providers", state: .running, providers: [.codex, .claudeCode, .geminiCLI])
        collapsedTile("Reconnecting", state: .unknown, providers: [.claudeCode])
    }

    @ViewBuilder
    private var momentTiles: some View {
        GalleryTile(
            title: "Finished",
            width: NotchLayoutMetrics.finishedPreferredWidth,
            height: notchHeight + NotchLayoutMetrics.finishedContentHeight,
            radius: 16,
            topPadding: expandedContentTop
        ) {
            FinishedFlashView(session: GallerySamples.finished(.completed))
                .frame(height: NotchLayoutMetrics.finishedContentHeight - DynamicIslandSpacing.expandedTop * 2)
        }
        GalleryTile(
            title: "Failed",
            width: NotchLayoutMetrics.finishedPreferredWidth,
            height: notchHeight + NotchLayoutMetrics.finishedContentHeight,
            radius: 16,
            topPadding: expandedContentTop
        ) {
            FinishedFlashView(session: GallerySamples.finished(.failed))
                .frame(height: NotchLayoutMetrics.finishedContentHeight - DynamicIslandSpacing.expandedTop * 2)
        }
        GalleryTile(
            title: "Needs input (observer only)",
            width: NotchLayoutMetrics.temporaryPreferredWidth,
            height: notchHeight + 56,
            radius: 18,
            topPadding: expandedContentTop
        ) {
            TemporaryActivityView(session: GallerySamples.observedWaiting, waitingCount: 1)
                .frame(height: 40)
        }
        GalleryTile(
            title: "Needs input, three waiting",
            width: NotchLayoutMetrics.temporaryPreferredWidth,
            height: notchHeight + 56,
            radius: 18,
            topPadding: expandedContentTop
        ) {
            TemporaryActivityView(session: GallerySamples.observedWaiting, waitingCount: 3)
                .frame(height: 40)
        }
    }

    @ViewBuilder
    private var promptTiles: some View {
        waitingTile("Command approval", session: GallerySamples.permission, position: 1, count: 1)
        waitingTile("Single question", session: GallerySamples.question(multiple: false), position: 1, count: 1)
        waitingTile("Several questions, paged 2 of 3", session: GallerySamples.question(multiple: true), position: 2, count: 3)
        waitingTile("Plan approval", session: GallerySamples.planApproval, position: 1, count: 1)
    }

    @ViewBuilder
    private var expandedTiles: some View {
        listTile("List", sessions: GallerySamples.listSessions, related: GallerySamples.relatedSessions)
        listTile("List, nothing running", sessions: [], related: [], lastFinished: GallerySamples.finished(.completed))
        MeasuredGalleryTile(
            title: "Detail",
            width: NotchLayoutMetrics.detailPreferredWidth,
            radius: 21,
            notchHeight: notchHeight,
            topPadding: expandedContentTop,
            clamp: { NotchLayoutMetrics.detailContentHeight(measured: $0, screenHeight: 900, notchHeight: notchHeight) }
        ) { report in
            AgentDetailView(
                session: GallerySamples.detail,
                parent: nil,
                children: [],
                onBack: {},
                onSelectSession: { _ in },
                onOpen: { _ in },
                canAnswer: false,
                onAnswer: { _, _, _ in },
                outerCornerRadius: 21,
                onIdealHeightChange: report
            )
        }
    }

    // MARK: Builders

    private var expandedContentTop: CGFloat { notchHeight + DynamicIslandSpacing.expandedTop }

    private func collapsedTile(_ title: String, state: AgentState, providers: [AgentProvider]) -> some View {
        GalleryTile(
            title: title,
            width: notchWidth + DynamicIslandSpacing.compactEarWidth(for: providers.count) * 2,
            height: notchHeight + 2,
            radius: 10
        ) {
            CollapsedNotchView(state: state, activeProviders: providers, activeCount: providers.count)
        }
    }

    private func waitingTile(_ title: String, session: AgentSession, position: Int, count: Int) -> some View {
        MeasuredGalleryTile(
            title: title,
            width: NotchLayoutMetrics.temporaryPreferredWidth,
            radius: 18,
            notchHeight: notchHeight,
            topPadding: expandedContentTop,
            clamp: { NotchLayoutMetrics.waitingContentHeight(measured: $0, screenHeight: 900, notchHeight: notchHeight) }
        ) { report in
            WaitingReplyView(
                session: session,
                waitingPosition: position,
                waitingCount: count,
                onPage: { _ in },
                canAnswer: true,
                onAnswer: { _, _, _ in },
                onOpenDetail: {},
                onIdealHeightChange: report
            )
        }
    }

    private func listTile(
        _ title: String,
        sessions: [AgentSession],
        related: [AgentSession],
        lastFinished: AgentSession? = nil
    ) -> some View {
        GalleryTile(
            title: title,
            width: NotchLayoutMetrics.listPreferredWidth,
            height: notchHeight
                + DynamicIslandSpacing.expandedTop
                + AgentListView.rowsHeight(for: sessions)
                + DynamicIslandSpacing.expandedBottom,
            radius: 20
        ) {
            AgentListView(
                sessions: sessions,
                relatedSessions: related,
                lastFinishedSession: lastFinished,
                topInset: expandedContentTop,
                menuBarHeight: notchHeight,
                onOpenSettings: {},
                onOpenActivityCenter: {},
                onSelect: { _ in }
            )
        }
    }
}

private let galleryTileWidth: CGFloat = 480

/// One island hanging from the top of a lit backdrop. The backdrop stands in
/// for a wallpaper so the black silhouette and its corner radius are visible.
private struct GalleryTile<Content: View>: View {
    let title: String
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    var topPadding: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [NotchWindowPalette.floatingSelected, NotchWindowPalette.floating],
                    startPoint: .top,
                    endPoint: .bottom
                )
                ZStack(alignment: .top) {
                    NotchShape(bottomRadius: radius).fill(NotchWindowPalette.background)
                    content.padding(.top, topPadding)
                }
                .frame(width: width, height: height, alignment: .top)
                .clipShape(NotchShape(bottomRadius: radius))
            }
            .frame(width: galleryTileWidth, height: height + 28, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: NotchWindowMetrics.sectionRadius, style: .continuous))
        }
    }
}

/// A tile whose height follows the content's reported ideal height, clamped
/// by the same `NotchLayoutMetrics` rule the live notch uses.
private struct MeasuredGalleryTile<Content: View>: View {
    let title: String
    let width: CGFloat
    let radius: CGFloat
    let notchHeight: CGFloat
    let topPadding: CGFloat
    let clamp: (CGFloat) -> CGFloat
    @ViewBuilder let content: (@escaping (CGFloat) -> Void) -> Content

    @State private var measured: CGFloat = 0

    var body: some View {
        GalleryTile(
            title: title,
            width: width,
            height: notchHeight + clamp(measured),
            radius: radius,
            topPadding: topPadding
        ) {
            content { height in
                guard abs(measured - height) >= 0.5 else { return }
                measured = height
            }
        }
    }
}

private enum GallerySamples {
    static func session(
        _ id: String,
        provider: AgentProvider = .codex,
        type: AgentEventType = .activity,
        task: String,
        activity: String,
        state: AgentState,
        project: String = "AgentsNotch",
        minutesAgo: Double = 4,
        parent: String? = nil,
        role: String? = nil,
        plan: AgentPlan? = nil,
        pending: AgentPendingReply? = nil
    ) -> AgentSession {
        AgentSession(event: AgentEvent(
            type: type,
            sessionId: "gallery:\(id)",
            provider: provider,
            task: task,
            activity: activity,
            state: state,
            timestamp: Date().addingTimeInterval(-minutesAgo * 60),
            workingDirectory: "/Users/demo/\(project)",
            parentSessionId: parent.map { "gallery:\($0)" },
            agentRole: role,
            plan: plan,
            pendingReply: pending
        ))
    }

    static let plan = AgentPlan(steps: [
        AgentStep(id: "a", title: "Fix multi-session attention fallback", status: .completed),
        AgentStep(id: "b", title: "Serialize session persistence saves", status: .completed),
        AgentStep(id: "c", title: "Add regression tests and run suite", status: .inProgress),
        AgentStep(id: "d", title: "Update the changelog", status: .pending),
    ])

    static func finished(_ state: AgentState) -> AgentSession {
        session(
            "finished-\(state.rawValue)",
            provider: .claudeCode,
            type: state == .failed ? .failed : .completed,
            task: "Refine authentication flow",
            activity: state == .failed ? "Build failed" : "Tests passed",
            state: state,
            project: "web-app",
            minutesAgo: 2
        )
    }

    static let observedWaiting = session(
        "observed",
        provider: .geminiCLI,
        type: .waiting,
        task: "Investigate flaky test",
        activity: "Waiting for input",
        state: .waitingForUser,
        project: "api-server"
    )

    static let permission = session(
        "permission",
        type: .waiting,
        task: "Ship release 0.4.0",
        activity: "Needs command approval",
        state: .waitingForUser,
        pending: AgentPendingReply(
            replyId: UUID(),
            kind: .permission,
            prompt: "Allow this command?",
            detail: "git push origin main --tags",
            grants: [.deny, .allow]
        )
    )

    static let planApproval = session(
        "plan-approval",
        provider: .claudeCode,
        type: .waiting,
        task: "Migrate settings storage",
        activity: "Plan ready for review",
        state: .waitingForUser,
        pending: AgentPendingReply(
            replyId: UUID(),
            kind: .plan,
            prompt: "Ready to start coding?",
            detail: "1. Move preferences into a typed store\n2. Migrate existing defaults on launch\n3. Delete the legacy keys after one release",
            grants: [.deny, .allow]
        )
    )

    static func question(multiple: Bool) -> AgentSession {
        let questions = multiple
            ? [
                AgentPromptQuestion(
                    text: "Which test runner should the suite use?",
                    header: "Test runner",
                    options: [
                        AgentPromptOption(id: "swift-testing", label: "Swift Testing"),
                        AgentPromptOption(id: "xctest", label: "XCTest"),
                    ],
                    allowsMultiple: false
                ),
                AgentPromptQuestion(
                    text: "Which platforms should CI cover?",
                    header: "CI platforms",
                    options: [
                        AgentPromptOption(id: "macos-15", label: "macOS 15 on Apple silicon runners"),
                        AgentPromptOption(id: "intel", label: "Intel"),
                    ],
                    allowsMultiple: true
                ),
            ]
            : [
                AgentPromptQuestion(
                    text: "How should expired sessions be handled?",
                    options: [
                        AgentPromptOption(id: "refresh", label: "Silently refresh the token and retry the request"),
                        AgentPromptOption(id: "logout", label: "Sign the user out and explain why"),
                        AgentPromptOption(id: "prompt", label: "Ask first"),
                    ],
                    allowsMultiple: false
                ),
            ]
        return session(
            multiple ? "questions" : "question",
            provider: .claudeCode,
            type: .waiting,
            task: "Refine authentication flow",
            activity: "Asking a question",
            state: .waitingForUser,
            pending: AgentPendingReply(
                replyId: UUID(),
                kind: .question,
                prompt: multiple ? "A few choices before I continue" : questions[0].text,
                questions: questions,
                grants: [.cancel]
            )
        )
    }

    static let orchestrator = session(
        "orchestrator",
        task: "Coordinate implementation review",
        activity: "Waiting for subagents",
        state: .running,
        minutesAgo: 18
    )

    static let listSessions: [AgentSession] = [
        session(
            "plan",
            task: "Add regression tests",
            activity: "Running swift test",
            state: .executingTool,
            minutesAgo: 7,
            plan: plan
        ),
        orchestrator,
        session(
            "thinking",
            provider: .claudeCode,
            task: "Review pull request #36",
            activity: "Reading NotchRootView.swift",
            state: .thinking,
            project: "web-app",
            minutesAgo: 1
        ),
    ]

    static let relatedSessions: [AgentSession] = listSessions + [
        session(
            "implementer",
            type: .fileChanged,
            task: "Implement plan presentation",
            activity: "Editing AgentExecutionView.swift",
            state: .editing,
            parent: "orchestrator",
            role: "implementer"
        ),
        session(
            "reviewer",
            type: .waiting,
            task: "Review simulator lifecycle",
            activity: "Needs review decision",
            state: .waitingForUser,
            parent: "orchestrator",
            role: "reviewer"
        ),
    ]

    static let detail: AgentSession = {
        var detail = session(
            "detail",
            type: .started,
            task: "Add regression tests",
            activity: "Starting",
            state: .starting,
            minutesAgo: 9,
            plan: plan
        )
        let steps: [(AgentEventType, String, AgentState, String?, Double)] = [
            (.toolStarted, "Using Read", .executingTool, nil, 8),
            (.fileChanged, "Editing SessionPersistence.swift", .editing, "Sources/SessionPersistence.swift", 6),
            (.toolStarted, "Running swift test", .executingTool, nil, 2),
        ]
        for (type, activity, state, file, minutesAgo) in steps {
            detail.apply(AgentEvent(
                type: type,
                sessionId: "gallery:detail",
                provider: .codex,
                activity: activity,
                state: state,
                timestamp: Date().addingTimeInterval(-minutesAgo * 60),
                workingDirectory: "/Users/demo/AgentsNotch",
                file: file
            ))
        }
        return detail
    }()
}

/// Owns the gallery window for the lifetime of the app; reopening reuses it.
@MainActor
enum DebugGalleryWindow {
    private static var controller: NSWindowController?

    static func show() {
        if controller == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Notch Gallery"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DebugGalleryView())
            window.center()
            controller = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        controller?.window?.makeKeyAndOrderFront(nil)
    }
}
#endif
