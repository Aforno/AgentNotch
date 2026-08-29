import AppKit
import Darwin
import Foundation

struct RunningAgentNotchInstance {
    let processIdentifier: pid_t
    let launchDate: Date
    let activate: () -> Bool
}

/// Exclusive lock so two overlapping launches cannot both become the owner.
/// The fcntl lock is released when the process exits, including crashes.
final class FileInstanceOwnershipLock {
    private let fd: Int32?
    private var holdsLock = false

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentNotch", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }

    init(fileURL: URL = FileInstanceOwnershipLock.defaultFileURL) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = Darwin.open(fileURL.path, O_CREAT | O_RDWR, mode_t(0o600))
        self.fd = fd >= 0 ? fd : nil
    }

    deinit {
        if holdsLock, let fd {
            var lock = flock()
            lock.l_type = Int16(F_UNLCK)
            _ = Darwin.fcntl(fd, F_SETLK, &lock)
        }
        if let fd {
            Darwin.close(fd)
        }
    }

    /// Returns false when another process already owns the instance lock.
    /// A missing lock file does not block launch; launch-date ordering still applies.
    /// `fcntl` locks are per-process, so two objects in the same process do not contend.
    func tryAcquire() -> Bool {
        guard !holdsLock else { return true }
        guard let fd else { return true }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        if Darwin.fcntl(fd, F_SETLK, &lock) == 0 {
            holdsLock = true
            return true
        }
        let error = errno
        return error != EAGAIN && error != EACCES
    }
}

/// Hands a repeated launch to a strictly older running Agent Notch process.
@MainActor
final class AppInstanceCoordinator: NSObject {
    static let activationNotification = Notification.Name(
        "com.afonsoferreira.AgentNotch.activateExistingInstance"
    )

    private let currentProcessIdentifier: pid_t
    private let runningInstances: () -> [RunningAgentNotchInstance]
    private let postActivationRequest: (pid_t?) -> Void
    private let tryAcquireOwnership: () -> Bool
    private let distributedCenter: DistributedNotificationCenter
    private var onActivationRequest: (() -> Void)?
    private var isObserving = false

    init(
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.afonsoferreira.AgentNotch",
        distributedCenter: DistributedNotificationCenter = .default(),
        runningInstances: (() -> [RunningAgentNotchInstance])? = nil,
        postActivationRequest: ((pid_t?) -> Void)? = nil,
        tryAcquireOwnership: (() -> Bool)? = nil,
        ownershipLock: FileInstanceOwnershipLock? = nil
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
                object: processIdentifier.map(String.init),
                userInfo: nil,
                deliverImmediately: true
            )
        }
        self.tryAcquireOwnership = tryAcquireOwnership
            ?? { ownershipLock?.tryAcquire() ?? true }
        super.init()
    }

    /// Yields only to a process that launched earlier than this one. A newer
    /// peer is not "the existing instance", so two overlapping launches cannot
    /// both hand off and quit. The ownership lock is the tie-breaker when
    /// launch dates are missing or a peer already claimed ownership.
    func handOffIfNeeded() -> Bool {
        let instances = runningInstances()
        let currentLaunchDate = instances
            .first { $0.processIdentifier == currentProcessIdentifier }?
            .launchDate
        let peers = instances.filter { $0.processIdentifier != currentProcessIdentifier }

        if let currentLaunchDate,
           let existing = peers
            .filter({ $0.launchDate < currentLaunchDate })
            .min(by: { $0.launchDate < $1.launchDate })
        {
            return handOff(to: existing)
        }

        if tryAcquireOwnership() {
            return false
        }

        if let peer = peers.min(by: { $0.launchDate < $1.launchDate }) {
            return handOff(to: peer)
        }

        postActivationRequest(nil)
        return true
    }

    private func handOff(to instance: RunningAgentNotchInstance) -> Bool {
        postActivationRequest(instance.processIdentifier)
        _ = instance.activate()
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
        if let object = notification.object as? String,
           object != String(currentProcessIdentifier)
        {
            return
        }
        onActivationRequest?()
    }
}
