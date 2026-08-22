import AgentsNotchCore
import Darwin
import Foundation
import os

enum HookProcessIO {
    private static let logger = Logger(subsystem: "com.afonsoferreira.AgentNotch", category: "hook")

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

    /// Claude expects no stdout for passive hook runs; every other provider
    /// receives an empty JSON object. Keep this contract in sync with
    /// docs/PROTOCOL.md.
    static func writePassiveResponse(for provider: AgentProvider, to descriptor: Int32 = STDOUT_FILENO) {
        guard provider != .claudeCode else { return }
        writeStdout(Data("{}\n".utf8), to: descriptor)
    }

    static func writeDecision(_ data: Data, to descriptor: Int32 = STDOUT_FILENO) {
        var payload = data
        if payload.last != 0x0A {
            payload.append(0x0A)
        }
        writeStdout(payload, to: descriptor)
    }

    private static func writeStdout(_ payload: Data, to descriptor: Int32) {
        payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress, !buffer.isEmpty else { return }
            _ = Darwin.write(descriptor, baseAddress, buffer.count)
        }
    }

    static func origin() -> AgentOrigin? {
        AgentOrigin.captured(
            environment: ProcessInfo.processInfo.environment,
            processIdentifier: getppid()
        )
    }

    static func sendEvent(_ event: AgentEvent, to socketURL: URL) {
        do {
            try UnixSocketClient.send(event, to: socketURL)
        } catch {
            logger.error(
                "Could not deliver \(event.type.rawValue, privacy: .public) event for \(event.provider.rawValue, privacy: .public) session \(event.sessionId, privacy: .private): \(String(describing: error), privacy: .public)"
            )
        }
    }
}

struct HookProcessInvocation: Sendable {
    let configuredProvider: AgentProvider
    let provider: AgentProvider
    let socketURL: URL
    let replySocketURL: URL
    let answersFromNotch: Bool
    let isSelfTest: Bool
    let skipCompatibilityHook: Bool

    /// Parses relay arguments. Unknown `--provider` values fall back to Codex
    /// but emit a stderr warning so misconfiguration is diagnosable; hooks'
    /// stdout stays reserved for the decision contract.
    static func parse(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        warn: (String) -> Void = { message in
            FileHandle.standardError.write(Data("Agent Notch hook: \(message)\n".utf8))
        }
    ) -> HookProcessInvocation {
        let knownProviders: Set<String> = [
            AgentProvider.codex.rawValue,
            AgentProvider.claudeCode.rawValue,
            AgentProvider.grok.rawValue,
            AgentProvider.openCode.rawValue,
            AgentProvider.geminiCLI.rawValue,
            AgentProvider.cursor.rawValue,
        ]
        var explicitProvider: AgentProvider?
        if let index = arguments.firstIndex(of: "--provider"), arguments.indices.contains(index + 1) {
            let rawValue = arguments[index + 1]
            let parsed = AgentProvider(rawValue: rawValue)
            if knownProviders.contains(parsed.rawValue) {
                explicitProvider = parsed
            } else {
                warn("unknown --provider '\(rawValue)'; falling back to codex")
            }
        }
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
        let replySocketURL: URL = {
            if let index = arguments.firstIndex(of: "--reply-socket"), arguments.indices.contains(index + 1) {
                return URL(fileURLWithPath: arguments[index + 1])
            }
            return AgentReplySocketLocation.defaultURL
        }()
        let grokNativeConfiguration = homeDirectoryURL
            .appendingPathComponent(".grok/hooks/agentnotch.json")
        let skipCompatibilityHook = GrokHookRouting.shouldSkipClaudeCompatibilityHook(
            grokHookEvent: grokHookEvent,
            configuredProvider: configuredProvider,
            hasNativeRelay: GrokHookRouting.configurationContainsNativeRelay(at: grokNativeConfiguration)
        )
        return HookProcessInvocation(
            configuredProvider: configuredProvider,
            provider: provider,
            socketURL: socketURL,
            replySocketURL: replySocketURL,
            answersFromNotch: arguments.contains("--answer"),
            isSelfTest: arguments.contains("--self-test"),
            skipCompatibilityHook: skipCompatibilityHook
        )
    }
}
