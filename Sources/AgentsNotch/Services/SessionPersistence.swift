import AgentsNotchCore
import Foundation

actor SessionPersistence {
    struct LoadResult: Sendable {
        let sessions: [AgentSession]
        let recoveryMessage: String?
        let needsRewrite: Bool
    }

    nonisolated let fileURL: URL
    private nonisolated let writeLock = NSLock()
    private let loadDelay: Duration?

    init(fileURL: URL? = nil, loadDelay: Duration? = nil) {
        self.loadDelay = loadDelay
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
        writeLock.lock()
        defer { writeLock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadResult(sessions: [], recoveryMessage: nil, needsRewrite: false)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let sessions = try JSONDecoder.agentsNotch.decode([AgentSession].self, from: data)
            return LoadResult(sessions: sessions, recoveryMessage: nil, needsRewrite: false)
        } catch {
            let backupURL = nextCorruptBackupURL()
            do {
                try FileManager.default.moveItem(at: fileURL, to: backupURL)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: backupURL.path
                )
                return LoadResult(
                    sessions: [],
                    recoveryMessage: "Recovered unreadable session history to \(backupURL.lastPathComponent).",
                    needsRewrite: true
                )
            } catch let recoveryError {
                return LoadResult(
                    sessions: [],
                    recoveryMessage: "Session history is unreadable and could not be recovered: \(recoveryError.localizedDescription)",
                    needsRewrite: false
                )
            }
        }
    }

    func save(_ sessions: [AgentSession]) -> String? {
        do {
            try saveSynchronously(sessions)
            return nil
        } catch {
            return "Could not save session history: \(error.localizedDescription)"
        }
    }

    nonisolated func saveSynchronously(_ sessions: [AgentSession]) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.agentsNotch.encode(sessions)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
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
