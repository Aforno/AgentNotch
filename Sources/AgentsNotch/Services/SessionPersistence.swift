import AgentsNotchCore
import Foundation

actor SessionPersistence {
    private final class WriteState: @unchecked Sendable {
        let lock = NSLock()
        var latestOrderedGeneration: UInt64 = 0
    }

    struct LoadResult: Sendable {
        let sessions: [AgentSession]
        let recoveryMessage: String?
        /// False only when unreadable history could not be moved aside. In that
        /// state, replacing the file could destroy the only recoverable copy.
        let canSafelyWrite: Bool
    }

    nonisolated let fileURL: URL
    private nonisolated let writeState = WriteState()
    private nonisolated let quarantineUnreadableFile: @Sendable (URL, URL) throws -> Void
    /// Test barrier for forcing an older actor save to overlap the synchronous
    /// termination write. Production instances leave it nil.
    private nonisolated let beforeOrderedSave: (@Sendable () -> Void)?
    private let loadDelay: Duration?
    private(set) var saveInvocationCount = 0

    init(
        fileURL: URL? = nil,
        loadDelay: Duration? = nil,
        quarantineUnreadableFile: (@Sendable (URL, URL) throws -> Void)? = nil,
        beforeOrderedSave: (@Sendable () -> Void)? = nil
    ) {
        self.loadDelay = loadDelay
        self.beforeOrderedSave = beforeOrderedSave
        self.quarantineUnreadableFile = quarantineUnreadableFile ?? { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        }
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support
                .appendingPathComponent("AgentsNotch", isDirectory: true)
                .appendingPathComponent("sessions.json")
        }
    }

    func load() async -> LoadResult {
        if let loadDelay {
            try? await Task.sleep(for: loadDelay)
        }
        return loadSynchronously()
    }

    private nonisolated func loadSynchronously() -> LoadResult {
        writeState.lock.lock()
        defer { writeState.lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(sessions: [], recoveryMessage: nil, canSafelyWrite: true)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let sessions = try JSONDecoder.agentsNotch.decode([AgentSession].self, from: data)
            return LoadResult(sessions: sessions, recoveryMessage: nil, canSafelyWrite: true)
        } catch {
            let backupURL = nextCorruptBackupURL()
            do {
                try quarantineUnreadableFile(fileURL, backupURL)
                return LoadResult(
                    sessions: [],
                    recoveryMessage: "Recovered unreadable session history to \(backupURL.lastPathComponent).",
                    canSafelyWrite: true
                )
            } catch let recoveryError {
                return LoadResult(
                    sessions: [],
                    recoveryMessage: "Session history is unreadable and could not be recovered: \(recoveryError.localizedDescription)",
                    canSafelyWrite: false
                )
            }
        }
    }

    func save(_ sessions: [AgentSession]) -> String? {
        saveInvocationCount += 1
        do {
            try saveSynchronously(sessions)
            return nil
        } catch {
            return "Could not save session history: \(error.localizedDescription)"
        }
    }

    func save(_ sessions: [AgentSession], generation: UInt64) -> String? {
        saveInvocationCount += 1
        beforeOrderedSave?()
        do {
            try saveSynchronously(sessions, generation: generation)
            return nil
        } catch {
            return "Could not save session history: \(error.localizedDescription)"
        }
    }

    nonisolated func saveSynchronously(_ sessions: [AgentSession]) throws {
        try writeSynchronously(sessions, generation: nil)
    }

    nonisolated func saveSynchronously(
        _ sessions: [AgentSession],
        generation: UInt64
    ) throws {
        try writeSynchronously(sessions, generation: generation)
    }

    private nonisolated func writeSynchronously(
        _ sessions: [AgentSession],
        generation: UInt64?
    ) throws {
        writeState.lock.lock()
        defer { writeState.lock.unlock() }
        if let generation, generation < writeState.latestOrderedGeneration {
            return
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.agentsNotch.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        if let generation {
            writeState.latestOrderedGeneration = generation
        }
    }

    private nonisolated func nextCorruptBackupURL() -> URL {
        let stem = fileURL.lastPathComponent + ".corrupt"
        var candidate = fileURL.deletingLastPathComponent().appendingPathComponent(stem)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = fileURL.deletingLastPathComponent().appendingPathComponent("\(stem).\(suffix)")
            suffix += 1
        }
        return candidate
    }
}
