import AgentsNotchCore
import AppKit
import Darwin

@MainActor
struct OriginActivationService {
    private let openURL: (URL) -> Bool
    private let processAlive: (Int32) -> Bool
    private let processStartedAt: (Int32) -> Date?
    private let activateProcess: (Int32) -> Bool

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
        }
    ) {
        self.openURL = openURL
        self.processAlive = processAlive
        self.processStartedAt = processStartedAt
        self.activateProcess = activateProcess
    }

    @discardableResult
    func open(_ session: AgentSession) -> Bool {
        if let applicationURL = session.applicationURL,
           Self.isAllowedApplicationURL(applicationURL, for: session.provider),
           openURL(applicationURL) {
            return true
        }

        if let origin = session.origin,
           origin.matchesRunningProcess(
               processAlive: processAlive,
               currentStartedAt: processStartedAt
           ),
           let processIdentifier = origin.processIdentifier,
           activateProcess(processIdentifier) {
            return true
        }

        if let bundleIdentifier = session.origin?.bundleIdentifier,
           let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first,
           application.activate() {
            return true
        }

        if let directory = session.workingDirectory {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory)])
            return true
        }
        return false
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
        guard let url = session.applicationURL else { return false }
        return isAllowedApplicationURL(url, for: session.provider)
    }

    func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
