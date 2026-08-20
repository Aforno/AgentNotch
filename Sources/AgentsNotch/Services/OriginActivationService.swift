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
    private let openBundle: (String) -> Bool
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
        openBundle: @escaping (String) -> Bool = { bundleIdentifier in
            if NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .activate() == true {
                return true
            }
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                return false
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, _ in }
            return true
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
        self.openBundle = openBundle
        self.runAppleScript = runAppleScript
        self.revealDirectory = revealDirectory
    }

    @discardableResult
    func open(_ session: AgentSession) -> Bool {
        if Self.canOpenApplication(for: session) {
            return open(session, action: .application)
        }
        if Self.canOpenTerminal(for: session) {
            return open(session, action: .terminal)
        }
        guard session.provider != .codex else { return false }
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
            let usesCodexThreadURL = codexThreadURL(for: session) != nil
            let usesSessionURL = session.applicationURL.map {
                isAllowedApplicationURL($0, for: session.provider)
            } ?? false
            let title = if usesCodexThreadURL {
                "Open in Codex"
            } else if usesSessionURL {
                "Open session"
            } else {
                "Open app"
            }
            destinations.append(OriginOpenDestination(
                action: .application,
                title: title,
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
        if destinations.isEmpty,
           session.provider != .codex,
           session.workingDirectory != nil {
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
        if codexThreadURL(for: session) != nil {
            return true
        }
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
        if let threadURL = Self.codexThreadURL(for: session) {
            return openURL(threadURL)
        }
        if let applicationURL = session.applicationURL,
           Self.isAllowedApplicationURL(applicationURL, for: session.provider),
           openURL(applicationURL) {
            return true
        }
        guard session.origin?.isGraphicalApplication == true else { return false }
        if activateOriginProcess(session) { return true }
        if let bundleIdentifier = session.origin?.bundleIdentifier,
           openBundle(bundleIdentifier) {
            return true
        }
        return false
    }

    static func codexThreadURL(for session: AgentSession) -> URL? {
        guard session.provider == .codex,
              let threadID = resolvedCodexThreadID(for: session),
              isSafeCodexThreadID(threadID),
              var components = URLComponents(string: "codex://threads")
        else {
            return nil
        }
        components.path = "/\(threadID)"
        return components.url
    }

    /// Children open the parent thread. Roots need index evidence so a helper ULID
    /// is not advertised as `codex://threads/<helper-id>`.
    private static func resolvedCodexThreadID(for session: AgentSession) -> String? {
        if let parentID = session.parentSessionId,
           let threadID = CodexSessionTitleResolver.threadID(fromCanonicalSessionID: parentID) {
            return threadID
        }
        guard session.hasOfficialSessionTitle else { return nil }
        return CodexSessionTitleResolver.threadID(fromCanonicalSessionID: session.id)
    }

    static func isSafeCodexThreadID(_ value: String) -> Bool {
        value.wholeMatch(of: /^[A-Za-z0-9_-]{1,128}$/) != nil
    }

    private func openTerminal(_ session: AgentSession) -> Bool {
        guard let origin = session.origin, origin.isTerminalEmulator else { return false }
        if let revealURL = Self.iTermRevealURL(for: origin), openURL(revealURL) {
            return true
        }
        if let script = Self.terminalFocusScript(for: origin), runAppleScript(script) {
            return true
        }
        if activateOriginProcess(session) { return true }
        if let bundleIdentifier = origin.bundleIdentifier ?? origin.terminalProgram.flatMap(
            AgentOrigin.bundleIdentifier(forProgram:)
        ), openBundle(bundleIdentifier) {
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
        return nil
    }

    static func iTermRevealURL(for origin: AgentOrigin) -> URL? {
        let program = origin.terminalProgram?.lowercased()
        guard origin.bundleIdentifier == "com.googlecode.iterm2" || program == "iterm.app",
              let sessionID = origin.terminalSessionIdentifier,
              isSafeSessionIdentifier(sessionID),
              var components = URLComponents(string: "iterm2:///reveal")
        else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "sessionid", value: sessionID)]
        return components.url
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
