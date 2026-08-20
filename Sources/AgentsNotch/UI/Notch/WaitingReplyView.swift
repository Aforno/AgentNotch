import AgentsNotchCore
import SwiftUI

/// Expanded attention surface for a prompt the user can answer from the notch.
struct WaitingReplyView: View {
    let session: AgentSession
    let waitingCount: Int
    let canAnswer: Bool
    let onAnswer: (AgentReplyDecision, String?) -> Void
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
                onAnswer(.deny, nil)
                return .handled
            case .return:
                if pending?.kind == .question, let first = pending?.options.first {
                    onAnswer(.option, first.id)
                } else {
                    onAnswer(.allow, nil)
                }
                return .handled
            default:
                if let number = Int(press.characters),
                   let option = pending?.options[safe: number - 1]
                {
                    onAnswer(.option, option.id)
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
    let onAnswer: (AgentReplyDecision, String?) -> Void

    var body: some View {
        if !pending.options.isEmpty {
            HStack(spacing: DynamicIslandSpacing.related) {
                ForEach(Array(pending.options.prefix(3))) { option in
                    replyButton(option.label, kind: .choice) {
                        onAnswer(.option, option.id)
                    }
                }
            }
        } else {
            HStack(spacing: DynamicIslandSpacing.related) {
                if pending.allowsDeny {
                    replyButton(pending.kind == .plan ? "Keep planning" : "Deny", kind: .deny) {
                        onAnswer(.deny, nil)
                    }
                }
                if pending.allowsAllow {
                    replyButton(pending.kind == .plan ? "Start coding" : "Allow", kind: .allow) {
                        onAnswer(.allow, nil)
                    }
                }
            }
        }
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
