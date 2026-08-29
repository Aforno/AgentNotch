import AppKit
import Foundation

struct RunningAgentNotchInstance {
    let processIdentifier: pid_t
    let launchDate: Date
    let activate: () -> Bool
}

/// Hands a repeated launch to the oldest running Agent Notch process.
@MainActor
final class AppInstanceCoordinator: NSObject {
    static let activationNotification = Notification.Name(
        "com.afonsoferreira.AgentNotch.activateExistingInstance"
    )

    private let currentProcessIdentifier: pid_t
    private let runningInstances: () -> [RunningAgentNotchInstance]
    private let postActivationRequest: (pid_t) -> Void
    private let distributedCenter: DistributedNotificationCenter
    private var onActivationRequest: (() -> Void)?
    private var isObserving = false

    init(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.afonsoferreira.AgentNotch",
        distributedCenter: DistributedNotificationCenter = .default(),
        runningInstances: (() -> [RunningAgentNotchInstance])? = nil,
        postActivationRequest: ((pid_t) -> Void)? = nil
    ) {
        self.currentProcessIdentifier = currentProcessIdentifier
        self.distributedCenter = distributedCenter
        self.runningInstances = runningInstances ?? {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map { application in
                RunningAgentNotchInstance(
                    processIdentifier: application.processIdentifier,
                    launchDate: application.launchDate ?? .distantFuture,
                    activate: {
                        application.activate(options: [.activateAllWindows])
                    }
                )
            }
        }
        self.postActivationRequest = postActivationRequest ?? { processIdentifier in
            distributedCenter.postNotificationName(
                Self.activationNotification,
                object: String(processIdentifier),
                userInfo: nil,
                deliverImmediately: true
            )
        }
        super.init()
    }

    func handOffIfNeeded() -> Bool {
        guard let existing = runningInstances()
            .filter({ $0.processIdentifier != currentProcessIdentifier })
            .min(by: { $0.launchDate < $1.launchDate })
        else { return false }

        postActivationRequest(existing.processIdentifier)
        _ = existing.activate()
        return true
    }

    func startReceiving(onActivationRequest: @escaping () -> Void) {
        self.onActivationRequest = onActivationRequest
        guard !isObserving else { return }
        isObserving = true
        distributedCenter.addObserver(
            self,
            selector: #selector(handleActivationRequest),
            name: Self.activationNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func stopReceiving() {
        guard isObserving else { return }
        distributedCenter.removeObserver(
            self,
            name: Self.activationNotification,
            object: nil
        )
        isObserving = false
        onActivationRequest = nil
    }

    @objc private func handleActivationRequest(_ notification: Notification) {
        guard notification.object as? String == String(currentProcessIdentifier) else { return }
        onActivationRequest?()
    }
}
