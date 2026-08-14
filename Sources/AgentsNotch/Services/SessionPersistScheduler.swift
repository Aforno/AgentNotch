import AgentsNotchCore
import Foundation

/// Debounces session-history writes so a burst of hook events cannot overwrite
/// a newer snapshot with an older one.
@MainActor
final class SessionPersistScheduler {
    private let persistence: SessionPersistence
    private let debounceDuration: Duration
    private let maximumDelay: Duration
    private var persistTask: Task<Void, Never>?
    private var persistDeadlineTask: Task<Void, Never>?
    /// Protects an unreadable history file when it could not be quarantined.
    private(set) var writesAllowed = false

    init(
        persistence: SessionPersistence,
        debounceDuration: Duration,
        maximumDelay: Duration
    ) {
        self.persistence = persistence
        self.debounceDuration = debounceDuration
        self.maximumDelay = maximumDelay
    }

    func setWritesAllowed(_ allowed: Bool) {
        writesAllowed = allowed
    }

    func cancelPending() {
        persistTask?.cancel()
        persistTask = nil
        persistDeadlineTask?.cancel()
        persistDeadlineTask = nil
    }

    func schedule(
        snapshot: @escaping @MainActor () -> [AgentSession],
        onResult: @escaping @MainActor (String?) -> Void
    ) {
        guard writesAllowed else { return }
        if persistDeadlineTask == nil {
            persistDeadlineTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: maximumDelay)
                } catch {
                    return
                }
                await flush(snapshot: snapshot, onResult: onResult)
            }
        }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounceDuration)
            } catch {
                return
            }
            await flush(snapshot: snapshot, onResult: onResult)
        }
    }

    func flush(
        snapshot: @escaping @MainActor () -> [AgentSession],
        onResult: @escaping @MainActor (String?) -> Void
    ) async {
        cancelPending()
        guard writesAllowed else { return }
        onResult(await persistence.save(snapshot()))
    }

    func flushSynchronously(snapshot: [AgentSession]) throws {
        try persistence.saveSynchronously(snapshot)
    }
}
