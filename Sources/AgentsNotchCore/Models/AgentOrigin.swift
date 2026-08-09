import Foundation

/// Best-effort local context for returning the user to the application that
/// launched an agent. Every field is optional because provider hooks expose
/// different amounts of process and terminal metadata.
public struct AgentOrigin: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?
    public var terminalProgram: String?
    public var terminalSessionIdentifier: String?
    public var tty: String?

    public init(
        bundleIdentifier: String? = nil,
        processIdentifier: Int32? = nil,
        terminalProgram: String? = nil,
        terminalSessionIdentifier: String? = nil,
        tty: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.terminalProgram = terminalProgram
        self.terminalSessionIdentifier = terminalSessionIdentifier
        self.tty = tty
    }

    public var isEmpty: Bool {
        bundleIdentifier == nil
            && processIdentifier == nil
            && terminalProgram == nil
            && terminalSessionIdentifier == nil
            && tty == nil
    }
}
