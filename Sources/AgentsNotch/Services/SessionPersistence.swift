import AgentsNotchCore
import Foundation

actor SessionPersistence {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = support
                .appendingPathComponent("AgentsNotch", isDirectory: true)
                .appendingPathComponent("sessions.json")
        }
    }

    func load() -> [AgentSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.agentsNotch.decode([AgentSession].self, from: data)) ?? []
    }

    func save(_ sessions: [AgentSession]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder.agentsNotch.encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best effort. Live monitoring remains authoritative.
        }
    }
}
