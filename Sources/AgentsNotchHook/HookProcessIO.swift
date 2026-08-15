import AgentsNotchCore
import Darwin
import Foundation

enum HookProcessIO {
    static func ignoreBrokenPipes() {
        _ = signal(SIGPIPE, SIG_IGN)
        _ = fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, 1)
    }

    /// Reads stdin up to the safety cap and drains any remainder so an oversized
    /// provider payload cannot observe EPIPE mid-write.
    static func readStdin() -> Data {
        let handle = FileHandle.standardInput
        let cap = AgentHookInput.maximumBytes + 1
        var data = (try? handle.read(upToCount: cap)) ?? Data()
        if data.count >= cap {
            while let chunk = try? handle.read(upToCount: 65_536), !chunk.isEmpty {
                // discard
            }
            if data.count > AgentHookInput.maximumBytes {
                data = data.prefix(AgentHookInput.maximumBytes + 1)
            }
        }
        return data
    }

    static func writePassiveResponse(for provider: AgentProvider) {
        guard provider != .claudeCode else { return }
        let payload = Data("{}\n".utf8)
        payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress, !buffer.isEmpty else { return }
            _ = Darwin.write(STDOUT_FILENO, baseAddress, buffer.count)
        }
    }

    static func origin() -> AgentOrigin? {
        let environment = ProcessInfo.processInfo.environment
        let terminalProgram = environment["TERM_PROGRAM"]
        let bundleIdentifier = environment["AGENTS_NOTCH_BUNDLE_IDENTIFIER"]
            ?? environment["__CFBundleIdentifier"]
            ?? terminalProgram.flatMap(bundleIdentifier(forTerminalProgram:))
        let sessionIdentifier = environment["TERM_SESSION_ID"]
            ?? environment["ITERM_SESSION_ID"]
            ?? environment["WEZTERM_PANE"]
            ?? environment["KITTY_WINDOW_ID"]
        let origin = AgentOrigin(
            bundleIdentifier: bundleIdentifier?.nonEmpty,
            processIdentifier: getppid(),
            terminalProgram: terminalProgram?.nonEmpty,
            terminalSessionIdentifier: sessionIdentifier?.nonEmpty,
            tty: environment["TTY"]?.nonEmpty
        )
        return origin.isEmpty ? nil : origin
    }

    private static func bundleIdentifier(forTerminalProgram program: String) -> String? {
        switch program.lowercased() {
        case "apple_terminal": "com.apple.Terminal"
        case "iterm.app": "com.googlecode.iterm2"
        case "vscode": "com.microsoft.VSCode"
        case "warpterminal": "dev.warp.Warp-Stable"
        case "wezterm": "com.github.wez.wezterm"
        case "ghostty": "com.mitchellh.ghostty"
        default: nil
        }
    }
}

struct HookProcessInvocation: Sendable {
    let configuredProvider: AgentProvider
    let provider: AgentProvider
    let socketURL: URL
    let isSelfTest: Bool
    let skipCompatibilityHook: Bool

    static func parse(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HookProcessInvocation {
        let explicitProvider: AgentProvider? = {
            if let index = arguments.firstIndex(of: "--provider"), arguments.indices.contains(index + 1) {
                return AgentProvider(rawValue: arguments[index + 1])
            }
            return nil
        }()
        let configuredProvider = explicitProvider ?? .codex
        let grokHookEvent = environment["GROK_HOOK_EVENT"]
        let provider = GrokHookRouting.resolvedProvider(
            explicit: explicitProvider,
            grokHookEvent: grokHookEvent
        )
        let socketURL: URL = {
            if let index = arguments.firstIndex(of: "--socket"), arguments.indices.contains(index + 1) {
                return URL(fileURLWithPath: arguments[index + 1])
            }
            return AgentSocketLocation.defaultURL
        }()
        let grokNativeConfiguration = homeDirectoryURL
            .appendingPathComponent(".grok/hooks/agentsnotch.json")
        let skipCompatibilityHook = GrokHookRouting.shouldSkipClaudeCompatibilityHook(
            grokHookEvent: grokHookEvent,
            configuredProvider: configuredProvider,
            hasNativeRelay: GrokHookRouting.configurationContainsNativeRelay(at: grokNativeConfiguration)
        )
        return HookProcessInvocation(
            configuredProvider: configuredProvider,
            provider: provider,
            socketURL: socketURL,
            isSelfTest: arguments.contains("--self-test"),
            skipCompatibilityHook: skipCompatibilityHook
        )
    }
}
