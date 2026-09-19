import AgentsNotchCore
import AppKit
import SwiftUI

struct WaitingReplyView: View {
    let session: AgentSession
    /// 1-based index of `session` among the waiting sessions.
    let waitingPosition: Int
    let waitingCount: Int
    /// Moves to the previous (-1) or next (+1) waiting session.
    let onPage: (Int) -> Void
    let canAnswer: Bool
    let onAnswer: (AgentReplyDecision, String?, [String: [String]]?) -> Void
    let onOpenDetail: () -> Void
    let onIdealHeightChange: (CGFloat) -> Void

    @AppStorage(AppPreferences.Key.privacyModeEnabled) private var privacyModeEnabled = false
    @FocusState private var isFocused: Bool
    @State private var isPointerInside = false
    @State private var requestsShortcutFocus = false
    @State private var isWindowKey = false
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private var shortcutsActive: Bool {
        requestsShortcutFocus && isPointerInside && isWindowKey && isFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
            header
                .padding(.horizontal, DynamicIslandSpacing.outer)
                .onHeightChange { height in
                    headerHeight = height
                    reportIdealHeight()
                }
            if privacyModeEnabled {
                Text("Approve in the source app")
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .padding(.horizontal, DynamicIslandSpacing.outer)
                    .onHeightChange { height in
                        contentHeight = height
                        reportIdealHeight()
                    }
            } else {
                scrollingContent
            }
        }
        .padding(.bottom, DynamicIslandSpacing.outer)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .contentShape(Rectangle())
        .background(NotchWindowKeyBridge(
            wantsKeyWindow: requestsShortcutFocus,
            isKeyWindow: $isWindowKey
        ))
        .onHover { hovering in
            isPointerInside = hovering
            if !hovering {
                requestsShortcutFocus = false
                isFocused = false
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            guard isPointerInside else { return }
            isFocused = true
            requestsShortcutFocus = true
        })
        .onChange(of: isWindowKey) { _, keyWindow in
            isFocused = keyWindow && requestsShortcutFocus && isPointerInside
        }
        .onChange(of: pending?.replyId) { _, _ in
            isFocused = isWindowKey && requestsShortcutFocus && isPointerInside
        }
        .onDisappear {
            requestsShortcutFocus = false
            isFocused = false
        }
        .onKeyPress { press in
            guard shortcutsActive, canAnswer, !privacyModeEnabled else { return .ignored }
            switch press.key {
            case .escape:
                guard let pending else { return .ignored }
                if pending.allowsCancel {
                    onAnswer(.cancel, nil, nil)
                } else if pending.allowsDeny {
                    onAnswer(.deny, nil, nil)
                } else {
                    return .ignored
                }
                return .handled
            case .return:
                guard pending?.questions?.isEmpty != false, pending?.allowsAllow == true else {
                    return .ignored
                }
                onAnswer(.allow, nil, nil)
                return .handled
            default:
                if pending?.questions?.count == 1,
                   pending?.questions?.first?.allowsMultiple == false,
                   let number = Int(press.characters),
                   let question = pending?.questions?.first,
                   let option = question.options[safe: number - 1]
                {
                    onAnswer(.option, option.id, [question.text: [option.label]])
                    return .handled
                }
                return .ignored
            }
        }
    }

    private var pending: AgentPendingReply? { session.pendingReply }

    /// A long prompt, a detail block, and a wide option grid can together
    /// outgrow the notch's maximum height. Scrolling keeps every action
    /// reachable; the faded edge is the only cue, since indicators are hidden.
    private var scrollingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                promptBlock
                actions
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
        .notchScrollEdgeFade()
    }

    /// Chrome is the top inset above the header plus the two fixed gaps the
    /// body adds around it.
    private func reportIdealHeight() {
        guard headerHeight > 0, contentHeight > 0 else { return }
        onIdealHeightChange(
            DynamicIslandSpacing.expandedTop
                + headerHeight
                + DynamicIslandSpacing.related
                + contentHeight
                + DynamicIslandSpacing.outer
        )
    }

    private var header: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: session.state, size: 8)
            ProviderIconView(provider: session.provider, size: 14)
                .foregroundStyle(NotchWindowPalette.primaryText)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DynamicIslandSpacing.tight) {
                    Text(session.provider.displayName)
                        .font(NotchWindowFont.captionEmphasis)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                    Text("·")
                        .foregroundStyle(NotchWindowPalette.quaternaryText)
                    Text(projectName)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }
                .lineLimit(1)
                Text(session.currentActivity)
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if waitingCount > 1 {
                waitingPager
            }
            Button(action: onOpenDetail) {
                Image(systemName: "chevron.right")
                    .font(NotchWindowFont.captionEmphasis)
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
            }
            .buttonStyle(NotchGlyphButtonStyle())
            .help("Open details")
            .accessibilityLabel("Open details")
        }
    }

    private var waitingPager: some View {
        HStack(spacing: 0) {
            pagerButton("chevron.left", label: "Previous waiting agent") { onPage(-1) }
            Text("\(waitingPosition)/\(waitingCount)")
                .font(NotchWindowFont.footnoteEmphasis)
                .monospacedDigit()
                .foregroundStyle(.orange)
                .accessibilityLabel("\(waitingPosition) of \(waitingCount) waiting")
            pagerButton("chevron.right", label: "Next waiting agent") { onPage(1) }
        }
    }

    private func pagerButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NotchWindowPalette.secondaryText)
        }
        .buttonStyle(NotchGlyphButtonStyle(size: 20))
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var promptBlock: some View {
        if let pending {
            Text(pending.prompt)
                .font(NotchWindowFont.subtitle)
                .foregroundStyle(NotchWindowPalette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = pending.detail, pending.kind != .question {
                Text(detail)
                    .font(NotchWindowFont.monoCaption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NotchWindowPalette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    // Never truncate: an approval must show the whole command.
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if canAnswer, let pending {
            WaitingReplyActions(
                pending: pending,
                showsKeyboardHints: true,
                keyboardHintsActive: shortcutsActive,
                onAnswer: onAnswer
            )
            .id(pending.replyId)
        }
    }

    private var projectName: String {
        return session.projectName ?? session.task
    }
}

/// Observes key-window ownership from a deliberate click and releases it when
/// shortcut focus ends. SwiftUI focus alone does not key a nonactivating panel.
private struct NotchWindowKeyBridge: NSViewRepresentable {
    let wantsKeyWindow: Bool
    @Binding var isKeyWindow: Bool

    func makeNSView(context: Context) -> NotchWindowKeyBridgeView {
        let view = NotchWindowKeyBridgeView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NotchWindowKeyBridgeView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NotchWindowKeyBridgeView) {
        let keyWindow = $isKeyWindow
        view.onKeyWindowChange = { value in
            DispatchQueue.main.async {
                guard keyWindow.wrappedValue != value else { return }
                keyWindow.wrappedValue = value
            }
        }
        view.update(wantsKeyWindow: wantsKeyWindow)
    }
}

@MainActor
private final class NotchWindowKeyBridgeView: NSView {
    var onKeyWindowChange: ((Bool) -> Void)?

    private var wantsKeyWindow = false
    private weak var observedWindow: NSWindow?
    private nonisolated(unsafe) var observations: [NSObjectProtocol] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            if newWindow == nil, wantsKeyWindow, window?.isKeyWindow == true {
                window?.resignKey()
            }
            stopObservingWindow()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindow()
        publishKeyWindowState()
    }

    deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
    }

    func update(wantsKeyWindow: Bool) {
        let didEndRequest = self.wantsKeyWindow && !wantsKeyWindow
        self.wantsKeyWindow = wantsKeyWindow
        if didEndRequest, window?.isKeyWindow == true {
            window?.resignKey()
        }
        publishKeyWindowState()
    }

    private func observeWindow() {
        guard let window, observedWindow !== window else { return }
        stopObservingWindow()
        observedWindow = window
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observations.append(center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.publishKeyWindowState()
                }
            })
        }
    }

    private func stopObservingWindow() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        observedWindow = nil
    }

    private func publishKeyWindowState() {
        onKeyWindowChange?(window?.isKeyWindow == true)
    }
}

struct WaitingReplyActions: View {
    let pending: AgentPendingReply
    /// Only the notch prompt installs the key handler, so only it may advertise
    /// the shortcuts. The same actions rendered in the detail pane do not.
    var showsKeyboardHints = false
    /// Hints render dimmed until a click gives the prompt keyboard focus.
    var keyboardHintsActive = false
    let onAnswer: (AgentReplyDecision, String?, [String: [String]]?) -> Void
    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        if let questions = pending.questions, !questions.isEmpty {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                ForEach(questions) { question in
                    if questions.count > 1 {
                        Text(question.header ?? question.text)
                            .font(NotchWindowFont.captionEmphasis)
                            .foregroundStyle(NotchWindowPalette.secondaryText)
                    }
                    // Full-width rows so long labels wrap instead of truncating.
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(question.options.enumerated()), id: \.element.id) { index, option in
                            let selected = isSelected(option, for: question)
                            replyButton(
                                option.label,
                                emphasis: selected ? .primary : .neutral,
                                shortcut: digitShortcut(for: index, in: questions, question: question),
                                selected: selected,
                                wraps: true
                            ) {
                                select(option, for: question)
                                if questions.count == 1, !question.allowsMultiple {
                                    onAnswer(.option, option.id, [question.text: [option.label]])
                                }
                            }
                        }
                    }
                }
                if questions.count > 1 || questions.contains(where: \.allowsMultiple) {
                    replyButton(submitTitle, emphasis: .primary) {
                        onAnswer(.option, nil, selectedAnswers(for: questions))
                    }
                    .disabled(!hasCompleteAnswers(for: questions))
                    if let unanswered = questions.first(where: { selections[$0.text]?.isEmpty != false }) {
                        Text("Still needs: \(unanswered.header ?? unanswered.text)")
                            .font(NotchWindowFont.footnote)
                            .foregroundStyle(NotchWindowPalette.tertiaryText)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            HStack(spacing: DynamicIslandSpacing.related) {
                if pending.allowsDeny {
                    replyButton(
                        pending.kind == .plan ? "Keep planning" : "Deny",
                        emphasis: .neutral,
                        // Escape resolves to cancel when both are offered.
                        shortcut: pending.allowsCancel ? nil : hint("esc")
                    ) {
                        onAnswer(.deny, nil, nil)
                    }
                }
                if pending.allowsCancel {
                    replyButton("Cancel", emphasis: .neutral, shortcut: hint("esc")) {
                        onAnswer(.cancel, nil, nil)
                    }
                }
                if pending.allowsAllow {
                    replyButton(
                        pending.kind == .plan ? "Start coding" : "Allow",
                        emphasis: .primary,
                        shortcut: hint("⏎")
                    ) {
                        onAnswer(.allow, nil, nil)
                    }
                }
            }
        }
    }

    private var submitTitle: String {
        let count = selections.values.reduce(0) { $0 + $1.count }
        return count == 0 ? "Submit answers" : "Submit answers (\(count))"
    }

    private func hint(_ label: String) -> String? {
        showsKeyboardHints ? label : nil
    }

    /// Digits only pick an option when a single-select question is the whole
    /// prompt, which mirrors the key handler exactly.
    private func digitShortcut(
        for index: Int,
        in questions: [AgentPromptQuestion],
        question: AgentPromptQuestion
    ) -> String? {
        guard showsKeyboardHints,
              questions.count == 1,
              !question.allowsMultiple,
              index < 9
        else { return nil }
        return "\(index + 1)"
    }

    private func isSelected(_ option: AgentPromptOption, for question: AgentPromptQuestion) -> Bool {
        selections[question.text]?.contains(option.label) == true
    }

    private func select(_ option: AgentPromptOption, for question: AgentPromptQuestion) {
        if question.allowsMultiple {
            var values = selections[question.text] ?? []
            if !values.insert(option.label).inserted { values.remove(option.label) }
            selections[question.text] = values
        } else {
            selections[question.text] = [option.label]
        }
    }

    private func selectedAnswers(for questions: [AgentPromptQuestion]) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: questions.map { question in
            let selected = question.options.map(\.label).filter {
                selections[question.text]?.contains($0) == true
            }
            return (question.text, selected)
        })
    }

    private func hasCompleteAnswers(for questions: [AgentPromptQuestion]) -> Bool {
        questions.allSatisfy { selections[$0.text]?.isEmpty == false }
    }

    private func replyButton(
        _ title: String,
        emphasis: NotchActionEmphasis,
        shortcut: String? = nil,
        selected: Bool = false,
        wraps: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(wraps ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: wraps)
                    .frame(maxWidth: wraps ? .infinity : nil, alignment: .leading)
                if let shortcut {
                    NotchKeyCap(label: shortcut, isActive: keyboardHintsActive)
                }
            }
        }
        .buttonStyle(NotchActionButtonStyle(
            emphasis: emphasis,
            cornerRadius: wraps ? 10 : nil,
            expands: wraps
        ))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHintIfPresent(keyboardHintsActive ? shortcut.map(spokenShortcutHint) : nil)
    }

    private func spokenShortcutHint(_ shortcut: String) -> String {
        switch shortcut {
        case "⏎": "Press Return"
        case "esc": "Press Escape"
        default: "Press \(shortcut)"
        }
    }
}

private extension View {
    @ViewBuilder
    func accessibilityHintIfPresent(_ hint: String?) -> some View {
        if let hint {
            accessibilityHint(hint)
        } else {
            self
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
