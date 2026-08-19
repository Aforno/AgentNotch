import Darwin
import Foundation

/// Best-effort local context for returning the user to the application that
/// launched an agent. Every field is optional because provider hooks expose
/// different amounts of process and terminal metadata.
public struct AgentOrigin: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?
    public var processStartedAt: Date?
    public var terminalProgram: String?
    public var terminalSessionIdentifier: String?
    public var tty: String?

    public init(
        bundleIdentifier: String? = nil,
        processIdentifier: Int32? = nil,
        processStartedAt: Date? = nil,
        terminalProgram: String? = nil,
        terminalSessionIdentifier: String? = nil,
        tty: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.processStartedAt = processStartedAt
        self.terminalProgram = terminalProgram
        self.terminalSessionIdentifier = terminalSessionIdentifier
        self.tty = tty
    }

    public var isEmpty: Bool {
        bundleIdentifier == nil
            && processIdentifier == nil
            && processStartedAt == nil
            && terminalProgram == nil
            && terminalSessionIdentifier == nil
            && tty == nil
    }

    /// True when this origin's PID is still the process we recorded. A missing
    /// start time still matches a live PID so pre-identity history does not
    /// dismiss a live approval.
    public func matchesRunningProcess(
        processAlive: (Int32) -> Bool,
        currentStartedAt: (Int32) -> Date?
    ) -> Bool {
        guard let pid = processIdentifier, processAlive(pid) else { return false }
        guard let recordedStart = processStartedAt else { return true }
        guard let liveStart = currentStartedAt(pid) else { return false }
        return abs(liveStart.timeIntervalSince(recordedStart)) < 0.001
    }
}

package enum AgentProcessIdentity {
    package static func startedAt(for processIdentifier: Int32) -> Date? {
        guard processIdentifier > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let actualSize = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &info,
            expectedSize
        )
        guard actualSize == expectedSize else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        )
    }
}
