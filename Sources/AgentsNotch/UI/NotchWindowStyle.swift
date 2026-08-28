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
    /// Pointer-over fill, one rung below `raisedStrong` so hover reads as a
    /// hint rather than a selection.
    static let hover = Color.white.opacity(0.075)

    /// Hairline separator tone used throughout the notch.
    static let hairline = Color.white.opacity(0.08)

    // Text ladder. Four rungs only — anything dimmer than `quaternaryText`
    // is illegible on this surface, and `quaternaryText` itself must never be
    // the sole carrier of meaning.
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.5)
    /// Decorative chrome (separator dots, inactive glyphs) only.
    static let quaternaryText = Color.white.opacity(0.32)
}

/// Foreground for accent-filled notch actions. Blends the accent at the
/// primary fill opacity over the notch's black surface and picks black or
/// white from relative luminance so yellow, green, and orange stay readable.
enum NotchAccentContrast {
    static let primaryFillOpacity: CGFloat = 0.9
    /// Luminance at or above this value uses black text. Tuned so yellow,
    /// green, and orange get dark foreground; blue, pink, and red stay white.
    static let darkForegroundThreshold: CGFloat = 0.3

    static func usesDarkForeground(
        for accent: NSColor,
        fillOpacity: CGFloat = primaryFillOpacity
    ) -> Bool {
        blendedRelativeLuminance(of: accent, fillOpacity: fillOpacity) >= darkForegroundThreshold
    }

    static func foreground(
        for accent: NSColor,
        fillOpacity: CGFloat = primaryFillOpacity
    ) -> Color {
        usesDarkForeground(for: accent, fillOpacity: fillOpacity) ? .black : .white
    }

    static func blendedRelativeLuminance(
        of accent: NSColor,
        fillOpacity: CGFloat = primaryFillOpacity
    ) -> CGFloat {
        let rgb = sRGBComponents(of: accent)
        return relativeLuminance(
            red: rgb.red * fillOpacity,
            green: rgb.green * fillOpacity,
            blue: rgb.blue * fillOpacity
        )
    }

    static func relativeLuminance(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
        0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    static func sRGBComponents(of color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }

    private static func linearize(_ channel: CGFloat) -> CGFloat {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
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

/// One type scale for every surface. Sizes stop at 10pt: below that, the
/// muted text tones this app uses stop being readable on a laptop panel.
enum NotchWindowFont {
    static let display = Font.system(size: 17, weight: .semibold)
    static let title = Font.system(size: 15, weight: .semibold)
    static let subtitle = Font.system(size: 13, weight: .semibold)
    static let rowTitle = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 12, weight: .regular)
    static let bodyEmphasis = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionEmphasis = Font.system(size: 11, weight: .semibold)
    static let footnote = Font.system(size: 10, weight: .regular)
    static let footnoteEmphasis = Font.system(size: 10, weight: .semibold)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let control = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 10, weight: .regular, design: .monospaced)
    static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// Rounded digits for the collapsed-notch count and metric pills.
    static let counter = Font.system(size: 11, weight: .semibold, design: .rounded)
}

/// How an agent state reads on screen. The colour scale is deliberately short —
/// neutral, active, attention, success, failure — because the previous
/// nine-colour mapping put mint next to green and cyan next to blue at 8-12pt,
/// where they are indistinguishable. The finer distinction between thinking,
/// editing, and running is carried by `systemImage`, not by hue, so the state
/// survives greyscale and colour-blind viewing.
struct AgentStatePresentation {
    let color: Color
    /// Empty when `showsSpinner` is true.
    let systemImage: String
    let showsSpinner: Bool
}

func agentStatePresentation(for state: AgentState) -> AgentStatePresentation {
    switch state {
    case .waitingForUser:
        AgentStatePresentation(color: .orange, systemImage: "questionmark", showsSpinner: false)
    case .failed:
        AgentStatePresentation(color: .red, systemImage: "xmark", showsSpinner: false)
    case .completed:
        AgentStatePresentation(color: .green, systemImage: "checkmark", showsSpinner: false)
    case .editing:
        AgentStatePresentation(color: .blue, systemImage: "pencil", showsSpinner: false)
    case .thinking:
        AgentStatePresentation(color: .blue, systemImage: "ellipsis", showsSpinner: false)
    case .starting, .running, .executingTool:
        AgentStatePresentation(color: .blue, systemImage: "", showsSpinner: true)
    // Reconnecting is *not* proof of work. A spinner here made a session that
    // died while the app was quit look identical to one that is still running.
    case .unknown:
        AgentStatePresentation(
            color: NotchWindowPalette.tertiaryText,
            systemImage: "arrow.clockwise",
            showsSpinner: false
        )
    case .idle:
        AgentStatePresentation(
            color: NotchWindowPalette.quaternaryText,
            systemImage: "minus",
            showsSpinner: false
        )
    }
}

/// Single source of truth for agent state colours, shared by the notch's
/// `StateIndicator` and the Activity Center.
func agentStateColor(for state: AgentState) -> Color {
    agentStatePresentation(for: state).color
}

/// Plan and workflow step styling, shared by the row strip, the detail strip,
/// and the step list. Status is carried by glyph as well as colour.
enum StepStatusStyle {
    static func color(for status: AgentStepStatus) -> Color {
        switch status {
        case .pending: NotchWindowPalette.quaternaryText
        case .inProgress: .blue
        case .completed: .green
        case .failed: .red
        case .blocked: .orange
        }
    }

    static func systemImage(for status: AgentStepStatus) -> String {
        switch status {
        case .pending: "circle"
        case .inProgress: "circle.fill"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .blocked: "exclamationmark"
        }
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
