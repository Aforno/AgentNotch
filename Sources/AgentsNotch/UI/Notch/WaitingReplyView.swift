import AgentsNotchCore
import SwiftUI

/// Shows a waiting prompt and the actions available from the notch.
struct WaitingReplyView: View {
    let session: AgentSession
    let waitingCount: Int
    let canAnswer: Bool
    let onAnswer: (AgentReplyDecision, String?, [String: [String]]?) -> Void
    let onOpenDetail: () -> Void
    let onIdealHeightChange: (CGFloat) -> Void

    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
            header
            if privacyModeEnabled {
                Text("Approve in the source app")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                promptBlock
                actions
            }
        }
        .padding(.horizontal, DynamicIslandSpacing.outer)
        .padding(.bottom, DynamicIslandSpacing.standard)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onIdealHeightChange(geometry.size.height) }
                    .onChange(of: geometry.size.height) { _, height in
                        onIdealHeightChange(height)
                    }
            }
        }
        .focusable()
        .onKeyPress { press in
            guard canAnswer, !privacyModeEnabled else { return .ignored }
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

    private var header: some View {
        HStack(spacing: DynamicIslandSpacing.related) {
            StateIndicator(state: session.state, size: 8)
            ProviderIconView(provider: session.provider, size: 14)
                .foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DynamicIslandSpacing.tight) {
                    Text(session.provider.displayName)
                        .fontWeight(.semibold)
                    Text("·")
                        .foregroundStyle(.white.opacity(0.32))
                    Text(projectName)
                        .foregroundStyle(.white.opacity(0.66))
                }
                .font(.system(size: 11))
                .lineLimit(1)
                Text(session.currentActivity)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if waitingCount > 1 {
                Text("\(waitingCount) waiting")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Button(action: onOpenDetail) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open details")
        }
    }

    @ViewBuilder
    private var promptBlock: some View {
        if let pending {
            Text(pending.prompt)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = pending.detail, pending.kind != .question {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .lineLimit(4)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if canAnswer, let pending {
            WaitingReplyActions(pending: pending, onAnswer: onAnswer)
        }
    }

    private var projectName: String {
        guard let directory = session.workingDirectory else {
            return session.task
        }
        return URL(fileURLWithPath: directory).lastPathComponent
    }
}

struct WaitingReplyActions: View {
    let pending: AgentPendingReply
    let onAnswer: (AgentReplyDecision, String?, [String: [String]]?) -> Void
    @State private var selections: [String: Set<String>] = [:]

    var body: some View {
        if let questions = pending.questions, !questions.isEmpty {
            VStack(alignment: .leading, spacing: DynamicIslandSpacing.related) {
                ForEach(questions) { question in
                    if questions.count > 1 {
                        Text(question.header ?? question.text)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                        spacing: 6
                    ) {
                        ForEach(question.options) { option in
                            let kind: ReplyButtonKind = isSelected(option, for: question)
                                ? .allow
                                : .choice
                            replyButton(option.label, kind: kind) {
                                select(option, for: question)
                                if questions.count == 1, !question.allowsMultiple {
                                    onAnswer(.option, option.id, [question.text: [option.label]])
                                }
                            }
                        }
                    }
                }
                if questions.count > 1 || questions.contains(where: \.allowsMultiple) {
                    replyButton("Submit answers", kind: .allow) {
                        onAnswer(.option, nil, selectedAnswers(for: questions))
                    }
                    .disabled(!hasCompleteAnswers(for: questions))
                }
            }
        } else {
            HStack(spacing: DynamicIslandSpacing.related) {
                if pending.allowsDeny {
                    replyButton(pending.kind == .plan ? "Keep planning" : "Deny", kind: .deny) {
                        onAnswer(.deny, nil, nil)
                    }
                }
                if pending.allowsAllow {
                    replyButton(pending.kind == .plan ? "Start coding" : "Allow", kind: .allow) {
                        onAnswer(.allow, nil, nil)
                    }
                }
                if pending.allowsCancel {
                    replyButton("Cancel", kind: .deny) {
                        onAnswer(.cancel, nil, nil)
                    }
                }
            }
        }
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

    private func replyButton(_ title: String, kind: ReplyButtonKind, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(kind.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private enum ReplyButtonKind {
    case deny, allow, choice

    var color: Color {
        switch self {
        case .deny, .choice:
            Color.white.opacity(0.12)
        case .allow:
            Color.orange.opacity(0.85)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
