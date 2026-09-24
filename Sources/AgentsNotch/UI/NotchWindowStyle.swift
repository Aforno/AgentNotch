import AgentsNotchCore
import AppKit
import SwiftUI

/// Colors shared by the notch, Activity Center, and Settings windows.
enum NotchWindowPalette {
    static let background = Color.black

    /// Matches the notch's own card fill (`AgentExecutionView.executionCard`).
    static let raised = Color.white.opacity(0.055)
    static let raisedStrong = Color.white.opacity(0.1)
    static let raisedPressed = Color.white.opacity(0.135)
    static let raisedActive = Color.white.opacity(0.17)
    static let hover = Color.white.opacity(0.075)

    /// Opaque equivalents for floating panels, which order above arbitrary
    /// content and so have no black backdrop of their own to blend into.
    static let floating = Color(red: 0.13, green: 0.13, blue: 0.14)
    static let floatingSelected = Color(red: 0.24, green: 0.24, blue: 0.26)
    static let floatingHover = Color(red: 0.19, green: 0.19, blue: 0.21)

    static let hairline = Color.white.opacity(0.08)
    /// Control outlines at rest and under the pointer.
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.16)

    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.68)
    static let tertiaryText = Color.white.opacity(0.5)
    /// Decorative chrome (separator dots, inactive glyphs) only.
    static let quaternaryText = Color.white.opacity(0.32)

    /// The five state hues. `active` is the product's signature colour and
    /// also fills primary actions; the other three keep one meaning each.
    static let active = Color(nsColor: NotchBrand.active)
    static let attention = Color.orange
    static let success = Color.green
    static let failure = Color.red
}

/// AppKit-side brand colours, for code that needs an `NSColor`.
enum NotchBrand {
    /// A cool azure, bright enough to read as "working" on true black and
    /// distinct from the system accent the user may have picked.
    static let active = NSColor(srgbRed: 0.33, green: 0.71, blue: 1.0, alpha: 1)
}

/// Foreground for accent-filled notch actions. Each interaction fill is
/// blended over black, then uses whichever of black or white has more contrast.
enum NotchAccentContrast {
    static let primaryFillOpacity: CGFloat = 0.9

    static func usesDarkForeground(
        for accent: NSColor,
        fillOpacity: CGFloat = primaryFillOpacity
    ) -> Bool {
        let background = blendedRelativeLuminance(of: accent, fillOpacity: fillOpacity)
        return contrastRatio(foreground: 0, background: background)
            >= contrastRatio(foreground: 1, background: background)
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

    static func contrastRatio(foreground: CGFloat, background: CGFloat) -> CGFloat {
        (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
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

/// One type scale for every surface. Text sizes stop at 10pt: below that, the
/// muted text tones this app uses stop being readable on a laptop panel.
/// `glyph` and `emptyStateIcon` are for SF Symbols only, never for text.
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
    static let counter = Font.system(size: 11, weight: .semibold, design: .rounded)
    /// Settings row titles and floating-menu items, one step above body.
    static let label = Font.system(size: 13, weight: .medium)
    /// Disclosure chevrons and chip glyphs that sit beside footnote text.
    static let glyph = Font.system(size: 8, weight: .semibold)
    static let emptyStateIcon = Font.system(size: 20, weight: .light)
}

/// How an agent state reads on screen. Five hues only: idle, active,
/// attention, success, failure. Thinking, editing, and running share the
/// active hue and are distinguished by `systemImage`, so the state survives greyscale.
struct AgentStatePresentation {
    let color: Color
    /// Empty when `showsSpinner` is true.
    let systemImage: String
    let showsSpinner: Bool
}

func agentStatePresentation(for state: AgentState) -> AgentStatePresentation {
    switch state {
    case .waitingForUser:
        AgentStatePresentation(color: NotchWindowPalette.attention, systemImage: "questionmark", showsSpinner: false)
    case .failed:
        AgentStatePresentation(color: NotchWindowPalette.failure, systemImage: "xmark", showsSpinner: false)
    case .completed:
        AgentStatePresentation(color: NotchWindowPalette.success, systemImage: "checkmark", showsSpinner: false)
    case .editing:
        AgentStatePresentation(color: NotchWindowPalette.active, systemImage: "pencil", showsSpinner: false)
    case .thinking:
        AgentStatePresentation(color: NotchWindowPalette.active, systemImage: "ellipsis", showsSpinner: false)
    case .starting, .running, .executingTool:
        AgentStatePresentation(color: NotchWindowPalette.active, systemImage: "", showsSpinner: true)
    // Unknown is a static refresh glyph so reconnecting does not look like running.
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
        case .inProgress: NotchWindowPalette.active
        case .completed: NotchWindowPalette.success
        case .failed: NotchWindowPalette.failure
        case .blocked: NotchWindowPalette.attention
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

struct NotchHairline: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(NotchWindowPalette.hairline)
            .frame(height: 0.6)
            .padding(.leading, leadingInset)
    }
}
