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

    /// Terminal.app, iTerm, Ghostty, and the other emulators the relay maps.
    /// VS Code and Cursor report a TTY too; those stay graphical applications.
    public var isTerminalEmulator: Bool {
        if let program = normalizedTerminalProgram {
            if Self.terminalPrograms.contains(program) { return true }
            if Self.graphicalPrograms.contains(program) { return false }
        }
        if let bundle = bundleIdentifier {
            if Self.terminalBundles.contains(bundle) { return true }
            if Self.graphicalBundles.contains(bundle) { return false }
        }
        return false
    }

    /// Cursor, VS Code, and any other non-terminal GUI the relay captured.
    public var isGraphicalApplication: Bool {
        if isTerminalEmulator { return false }
        if let program = normalizedTerminalProgram, Self.graphicalPrograms.contains(program) {
            return true
        }
        guard let bundle = bundleIdentifier, !bundle.isEmpty else { return false }
        return !Self.terminalBundles.contains(bundle)
    }

    /// Builds origin from a hook's environment and parent process. `TTY` wins
    /// when the provider set it; otherwise the parent's controlling terminal.
    public static func captured(
        environment: [String: String],
        processIdentifier: Int32
    ) -> AgentOrigin? {
        captured(
            environment: environment,
            processIdentifier: processIdentifier,
            processStartedAt: AgentProcessIdentity.startedAt(for:),
            controllingTTY: AgentProcessIdentity.controllingTTY(for:)
        )
    }

    package static func captured(
        environment: [String: String],
        processIdentifier: Int32,
        processStartedAt: (Int32) -> Date?,
        controllingTTY: (Int32) -> String?
    ) -> AgentOrigin? {
        let terminalProgram = environment["TERM_PROGRAM"]?.nonEmpty
        let bundleIdentifier = environment["AGENTS_NOTCH_BUNDLE_IDENTIFIER"]?.nonEmpty
            ?? environment["__CFBundleIdentifier"]?.nonEmpty
            ?? terminalProgram.flatMap(bundleIdentifier(forProgram:))
        let sessionIdentifier = environment["TERM_SESSION_ID"]?.nonEmpty
            ?? environment["ITERM_SESSION_ID"]?.nonEmpty
            ?? environment["WEZTERM_PANE"]?.nonEmpty
            ?? environment["KITTY_WINDOW_ID"]?.nonEmpty
        let tty = environment["TTY"]?.nonEmpty ?? controllingTTY(processIdentifier)
        let origin = AgentOrigin(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier > 0 ? processIdentifier : nil,
            processStartedAt: processIdentifier > 0 ? processStartedAt(processIdentifier) : nil,
            terminalProgram: terminalProgram,
            terminalSessionIdentifier: sessionIdentifier,
            tty: tty
        )
        return origin.isEmpty ? nil : origin
    }

    public static func bundleIdentifier(forProgram program: String) -> String? {
        switch program.lowercased() {
        case "apple_terminal": "com.apple.Terminal"
        case "iterm.app": "com.googlecode.iterm2"
        case "vscode": "com.microsoft.VSCode"
        case "warpterminal": "dev.warp.Warp-Stable"
        case "wezterm": "com.github.wez.wezterm"
        case "ghostty": "com.mitchellh.ghostty"
        case "kitty": "net.kovidgoyal.kitty"
        default: nil
        }
    }

    private var normalizedTerminalProgram: String? {
        terminalProgram?.lowercased()
    }

    private static let terminalPrograms: Set<String> = [
        "apple_terminal",
        "iterm.app",
        "ghostty",
        "warpterminal",
        "wezterm",
        "kitty",
        "alacritty",
        "hyper",
        "tabby",
    ]

    private static let graphicalPrograms: Set<String> = [
        "vscode",
        "zed",
    ]

    private static let terminalBundles: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "io.alacritty",
        "co.zeit.hyper",
    ]

    private static let graphicalBundles: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "com.cursor.Cursor",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
    ]
}

package enum AgentProcessIdentity {
    package static func startedAt(for processIdentifier: Int32) -> Date? {
        guard let info = bsdInfo(for: processIdentifier) else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)
                + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        )
    }

    package static func controllingTTY(for processIdentifier: Int32) -> String? {
        guard let info = bsdInfo(for: processIdentifier) else { return nil }
        return ttyPath(fromDevice: info.e_tdev)
    }

    package static func ttyPath(fromDevice device: UInt32) -> String? {
        guard device != 0, device != UInt32.max else { return nil }
        guard let name = devname(dev_t(device), S_IFCHR) else { return nil }
        let path = "/dev/" + String(cString: name)
        return path.nonEmpty
    }

    private static func bsdInfo(for processIdentifier: Int32) -> proc_bsdinfo? {
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
        return info
    }
}
