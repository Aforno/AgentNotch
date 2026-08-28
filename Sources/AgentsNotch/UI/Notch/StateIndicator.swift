import AgentsNotchCore
import AppKit
import SwiftUI

struct StateIndicator: View {
    let state: AgentState
    var size: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if presentation.showsSpinner {
                StateSpinner(color: presentation.color, size: size, isAnimated: !reduceMotion)
            } else {
                Image(systemName: presentation.systemImage)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(presentation.color)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: presentation.color.opacity(state.needsAttention ? 0.7 : 0), radius: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.displayName)
        .accessibilityRemoveTraits(.isSelected)
    }

    private var presentation: AgentStatePresentation { agentStatePresentation(for: state) }
}

private struct StateSpinner: NSViewRepresentable {
    let color: Color
    let size: CGFloat
    let isAnimated: Bool

    func makeNSView(context: Context) -> CompositorSpinnerView {
        let view = CompositorSpinnerView()
        view.update(color: NSColor(color), size: size, isAnimated: isAnimated)
        return view
    }

    func updateNSView(_ nsView: CompositorSpinnerView, context: Context) {
        nsView.update(color: NSColor(color), size: size, isAnimated: isAnimated)
    }
}

private final class CompositorSpinnerView: NSView {
    private let spinnerLayer = CAShapeLayer()
    private nonisolated(unsafe) var occlusionObserver: NSObjectProtocol?
    private var spinnerSize: CGFloat = 12
    /// Reduce Motion replaces the rotation with a static ring rather than
    /// hiding the indicator entirely.
    private var isAnimated = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        spinnerLayer.fillColor = nil
        spinnerLayer.strokeStart = 0.12
        spinnerLayer.strokeEnd = 0.82
        spinnerLayer.lineCap = .round
        layer?.addSublayer(spinnerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: spinnerSize, height: spinnerSize)
    }

    override func layout() {
        super.layout()
        spinnerLayer.frame = bounds
        let lineWidth = max(1.25, spinnerSize * 0.16)
        spinnerLayer.lineWidth = lineWidth
        spinnerLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
            transform: nil
        )
        spinnerLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAnimationState() }
            }
        }
        updateAnimationState()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateAnimationState()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimationState()
    }

    func update(color: NSColor, size: CGFloat, isAnimated: Bool) {
        spinnerSize = size
        self.isAnimated = isAnimated
        spinnerLayer.strokeColor = color.cgColor
        invalidateIntrinsicContentSize()
        needsLayout = true
        updateAnimationState()
    }

    private func updateAnimationState() {
        let shouldAnimate = isAnimated
            && window?.occlusionState.contains(.visible) == true
            && !isHiddenOrHasHiddenAncestor
        if shouldAnimate {
            guard spinnerLayer.animation(forKey: "agentnotch.rotation") == nil else { return }
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = Double.pi * 2
            rotation.duration = 0.9
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            spinnerLayer.add(rotation, forKey: "agentnotch.rotation")
        } else {
            spinnerLayer.removeAnimation(forKey: "agentnotch.rotation")
        }
    }
}
