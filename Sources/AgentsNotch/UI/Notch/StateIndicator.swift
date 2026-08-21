import AgentsNotchCore
import AppKit
import SwiftUI

struct StateIndicator: View {
    let state: AgentState
    var size: CGFloat = 12

    var body: some View {
        Group {
            if state.showsSpinner {
                StateSpinner(color: color, size: size)
            } else {
                Image(systemName: state.systemImage)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(state.needsAttention ? 0.7 : 0), radius: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.displayName)
        .accessibilityRemoveTraits(.isSelected)
    }

    private var color: Color { agentStateColor(for: state) }
}

private struct StateSpinner: NSViewRepresentable {
    let color: Color
    let size: CGFloat

    func makeNSView(context: Context) -> CompositorSpinnerView {
        let view = CompositorSpinnerView()
        view.update(color: NSColor(color), size: size)
        return view
    }

    func updateNSView(_ nsView: CompositorSpinnerView, context: Context) {
        nsView.update(color: NSColor(color), size: size)
    }
}

private final class CompositorSpinnerView: NSView {
    private let spinnerLayer = CAShapeLayer()
    private nonisolated(unsafe) var occlusionObserver: NSObjectProtocol?
    private var spinnerSize: CGFloat = 12

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

    func update(color: NSColor, size: CGFloat) {
        spinnerSize = size
        spinnerLayer.strokeColor = color.cgColor
        invalidateIntrinsicContentSize()
        needsLayout = true
        updateAnimationState()
    }

    private func updateAnimationState() {
        let shouldAnimate = window?.occlusionState.contains(.visible) == true
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

private extension AgentState {
    var showsSpinner: Bool {
        switch self {
        case .starting, .running, .executingTool, .unknown: true
        case .idle, .thinking, .editing, .waitingForUser, .completed, .failed: false
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "minus"
        case .thinking: "ellipsis"
        case .editing: "pencil"
        case .waitingForUser: "questionmark"
        case .completed: "checkmark"
        case .failed: "xmark"
        case .starting, .running, .executingTool, .unknown: ""
        }
    }
}
