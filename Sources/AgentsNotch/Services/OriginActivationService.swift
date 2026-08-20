import AgentsNotchCore
import AppKit
import Darwin

enum OriginOpenAction: String, Equatable, Hashable, Sendable {
    case application
    case terminal
    case revealRepository
}

struct OriginOpenDestination: Equatable, Hashable {
    let action: OriginOpenAction
    let title: String
    let systemImage: String
}

@MainActor
struct OriginActivationService {
    private let openURL: (URL) -> Bool
    private let processAlive: (Int32) -> Bool
    private let processStartedAt: (Int32) -> Date?
    private let activateProcess: (Int32) -> Bool
    private let activateBundle: (String) -> Bool
    private let runAppleScript: (String) -> Bool
    private let revealDirectory: (String) -> Void

    init(
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        processAlive: @escaping (Int32) -> Bool = { pid in
            guard pid > 0 else { return false }
            return kill(pid, 0) == 0
        },
        processStartedAt: @escaping (Int32) -> Date? = { AgentProcessIdentity.startedAt(for: $0) },
        activateProcess: @escaping (Int32) -> Bool = { pid in
            guard let application = NSRunningApplication(processIdentifier: pid),
                  application.activationPolicy != .prohibited
            else { return false }
            return application.activate()
        },
        activateBundle: @escaping (String) -> Bool = { bundleIdentifier in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .activate() ?? false
        },
        runAppleScript: @escaping (String) -> Bool = { source in
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return false }
            _ = script.executeAndReturnError(&error)
            return error == nil
        },
        revealDirectory: @escaping (String) -> Void = { path in
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    ) {
        self.openURL = openURL
        self.processAlive = processAlive
        self.processStartedAt = processStartedAt
        self.activateProcess = activateProcess
        self.activateBundle = activateBundle
        self.runAppleScript = runAppleScript
        self.revealDirectory = revealDirectory
    }

    @discardableResult
    func open(_ session: AgentSession) -> Bool {
        if Self.canOpenApplication(for: session), open(session, action: .application) {
            return true
        }
        if Self.canOpenTerminal(for: session), open(session, action: .terminal) {
            return true
        }
        if activateOriginProcess(session) {
            return true
        }
        return open(session, action: .revealRepository)
    }

    @discardableResult
    func open(_ session: AgentSession, action: OriginOpenAction) -> Bool {
        switch action {
        case .application:
            return openApplication(session)
        case .terminal:
            return openTerminal(session)
        case .revealRepository:
            return revealRepository(session)
        }
    }

    static func destinations(for session: AgentSession) -> [OriginOpenDestination] {
        var destinations: [OriginOpenDestination] = []
        if canOpenApplication(for: session) {
            let usesSessionURL = session.applicationURL.map {
                isAllowedApplicationURL($0, for: session.provider)
            } ?? false
            destinations.append(OriginOpenDestination(
                action: .application,
                title: usesSessionURL ? "Open session" : "Open app",
                systemImage: "arrow.up.forward.app"
            ))
        }
        if canOpenTerminal(for: session) {
            destinations.append(OriginOpenDestination(
                action: .terminal,
                title: "Open terminal",
                systemImage: "terminal"
            ))
        }
        if destinations.isEmpty, session.workingDirectory != nil {
            destinations.append(OriginOpenDestination(
                action: .revealRepository,
                title: "Reveal repository",
                systemImage: "folder"
            ))
        }
        return destinations
    }

    static func isAllowedApplicationURL(_ url: URL, for provider: AgentProvider) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }
        let allowedHosts: Set<String> = switch provider {
        case .codex: ["chatgpt.com"]
        case .claudeCode: ["claude.ai"]
        case .grok: ["grok.com", "x.com"]
        case .geminiCLI: ["gemini.google.com"]
        case .openCode: ["opencode.ai"]
        case .cursor: ["cursor.com"]
        default: []
        }
        return allowedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func canOpenApplication(for session: AgentSession) -> Bool {
        if let url = session.applicationURL, isAllowedApplicationURL(url, for: session.provider) {
            return true
        }
        return session.origin?.isGraphicalApplication == true
    }

    static func canOpenTerminal(for session: AgentSession) -> Bool {
        session.origin?.isTerminalEmulator == true
    }

    func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func openApplication(_ session: AgentSession) -> Bool {
        if let applicationURL = session.applicationURL,
           Self.isAllowedApplicationURL(applicationURL, for: session.provider),
           openURL(applicationURL) {
            return true
        }
        guard session.origin?.isGraphicalApplication == true else { return false }
        if activateOriginProcess(session) { return true }
        if let bundleIdentifier = session.origin?.bundleIdentifier,
           activateBundle(bundleIdentifier) {
            return true
        }
        return false
    }

    private func openTerminal(_ session: AgentSession) -> Bool {
        guard let origin = session.origin, origin.isTerminalEmulator else { return false }
        if let script = Self.terminalFocusScript(for: origin), runAppleScript(script) {
            return true
        }
        if activateOriginProcess(session) { return true }
        if let bundleIdentifier = origin.bundleIdentifier ?? origin.terminalProgram.flatMap(
            AgentOrigin.bundleIdentifier(forProgram:)
        ), activateBundle(bundleIdentifier) {
            return true
        }
        return false
    }

    private func revealRepository(_ session: AgentSession) -> Bool {
        guard let directory = session.workingDirectory else { return false }
        revealDirectory(directory)
        return true
    }

    private func activateOriginProcess(_ session: AgentSession) -> Bool {
        guard let origin = session.origin,
              origin.matchesRunningProcess(
                  processAlive: processAlive,
                  currentStartedAt: processStartedAt
              ),
              let processIdentifier = origin.processIdentifier
        else { return false }
        return activateProcess(processIdentifier)
    }

    static func terminalFocusScript(for origin: AgentOrigin) -> String? {
        let program = origin.terminalProgram?.lowercased()
        if origin.bundleIdentifier == "com.apple.Terminal" || program == "apple_terminal" {
            guard let tty = origin.tty, isSafeTTY(tty) else { return nil }
            let full = appleScriptString(tty)
            let short = appleScriptString((tty as NSString).lastPathComponent)
            return """
            tell application "Terminal"
              activate
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is \(full) or tty of t ends with \(short) then
                    set selected of t to true
                    set frontmost of w to true
                    return
                  end if
                end repeat
              end repeat
            end tell
            """
        }
        if origin.bundleIdentifier == "com.googlecode.iterm2" || program == "iterm.app" {
            guard let sessionID = origin.terminalSessionIdentifier,
                  isSafeSessionIdentifier(sessionID)
            else { return nil }
            let escaped = appleScriptString(sessionID)
            return """
            tell application "iTerm"
              activate
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if (id of s as string) is \(escaped) then
                      select w
                      select t
                      select s
                      return
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """
        }
        return nil
    }

    static func isSafeTTY(_ tty: String) -> Bool {
        tty.wholeMatch(of: /^\/dev\/ttys?\d+$/) != nil
    }

    static func isSafeSessionIdentifier(_ value: String) -> Bool {
        guard (1...128).contains(value.count) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:."))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func appleScriptString(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
