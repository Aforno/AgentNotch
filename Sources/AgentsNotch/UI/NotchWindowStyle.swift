import AppKit
import SwiftUI

enum NotchWindowPalette {
    static let background = Color.black
    static let raised = Color.white.opacity(0.045)
    static let raisedStrong = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.14)
    static let strongBorder = Color.white.opacity(0.34)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.34)
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
        }
    }
}

extension View {
    func deepBlackWindowSurface() -> some View {
        background(NotchWindowPalette.background)
            .background(DeepBlackWindowConfigurator())
            .preferredColorScheme(.dark)
    }

    func notchPanel(cornerRadius: CGFloat = 10) -> some View {
        background(
            NotchWindowPalette.raised,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(NotchWindowPalette.border, lineWidth: 1)
        }
    }
}
