import AgentsNotchCore
import AppKit
import SwiftUI

/// Shared surface vocabulary for every window that should feel like an extension
/// of the notch itself: opaque near-black, borderless raised fills, hairline
/// separators, and a white-opacity text ladder.
enum NotchWindowPalette {
    static let background = Color.black

    /// Matches the notch's own card fill (`AgentExecutionView.executionCard`).
    static let raised = Color.white.opacity(0.055)
    static let raisedStrong = Color.white.opacity(0.1)
    static let raisedPressed = Color.white.opacity(0.135)

    /// Hairline separator tone used throughout the notch.
    static let hairline = Color.white.opacity(0.08)

    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.34)
}

/// The notch uses a small, tight radius scale and never `.black` weights.
enum NotchWindowMetrics {
    static let cardRadius: CGFloat = 9
    static let controlRadius: CGFloat = 8
    static let sectionRadius: CGFloat = 10

    static let rowInset: CGFloat = 12
    static let sectionSpacing: CGFloat = 18
    static let contentInset: CGFloat = 20
}

enum NotchWindowFont {
    static let display = Font.system(size: 17, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 12, weight: .regular)
    static let bodyEmphasis = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    static let footnote = Font.system(size: 10, weight: .regular)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let control = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 10, weight: .regular, design: .monospaced)
}

/// Single source of truth for agent state colours, shared by the notch's
/// `StateIndicator` and the Activity Center.
func agentStateColor(for state: AgentState) -> Color {
    switch state {
    case .waitingForUser: .orange
    case .failed: .red
    case .completed: .green
    case .editing: .mint
    case .thinking: .purple
    case .starting: .cyan
    case .running, .executingTool: .blue
    case .unknown: .secondary
    case .idle: NotchWindowPalette.tertiaryText
    }
}

private struct DeepBlackWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWhenAttached(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWhenAttached(nsView)
    }

    private func configureWhenAttached(_ view: NSView) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            window.isOpaque = true
            // Match Activity Center chrome: titled windows keep minimize and
            // live-resize traffic-light controls.
            if window.styleMask.contains(.titled) {
                window.styleMask.insert([.miniaturizable, .resizable])
            }
        }
    }
}

extension View {
    func deepBlackWindowSurface() -> some View {
        background(NotchWindowPalette.background)
            .background(DeepBlackWindowConfigurator())
            .preferredColorScheme(.dark)
    }

    /// Borderless raised surface, mirroring the notch's own cards.
    func notchPanel(
        cornerRadius: CGFloat = NotchWindowMetrics.sectionRadius,
        fill: Color = NotchWindowPalette.raised
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The notch's separator: 0.6pt at 8% white, optionally inset like the agent list.
struct NotchHairline: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(NotchWindowPalette.hairline)
            .frame(height: 0.6)
            .padding(.leading, leadingInset)
    }
}
