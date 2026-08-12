import CoreGraphics
import Foundation

/// Coalesces SwiftUI size reports and applies only the newest frame request on
/// the next main-run-loop turn. This keeps NSWindow mutation outside the
/// NSHostingView constraint pass that produced recursive display-cycle crashes.
@MainActor
final class NotchPanelFrameScheduler {
    typealias FrameUpdate = (CGSize, Bool) -> Void

    private let apply: FrameUpdate
    private var pendingUpdate: (size: CGSize, animated: Bool)?
    private var isScheduled = false

    init(apply: @escaping FrameUpdate) {
        self.apply = apply
    }

    func schedule(size: CGSize, animated: Bool) {
        pendingUpdate = (size, animated)
        guard !isScheduled else { return }
        isScheduled = true

        DispatchQueue.main.async { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        isScheduled = false
        guard let update = pendingUpdate else { return }
        pendingUpdate = nil
        apply(update.size, update.animated)
    }
}
