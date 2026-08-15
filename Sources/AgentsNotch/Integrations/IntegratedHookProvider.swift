import AgentsNotchCore
import Foundation

/// Closed set of providers that install observer hooks. Adding a case without
/// a timeout unit fails to compile.
enum IntegratedHookProvider: String, CaseIterable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case grok
    case openCode = "opencode"
    case geminiCLI = "gemini-cli"
    case cursor

    var provider: AgentProvider { AgentProvider(rawValue: rawValue) }

    init?(provider: AgentProvider) {
        self.init(rawValue: provider.rawValue)
    }

    var timeoutUnit: HookTimeoutUnit {
        switch self {
        case .geminiCLI:
            .milliseconds
        case .codex, .claudeCode, .grok, .openCode, .cursor:
            .seconds
        }
    }

    func timeout(for eventName: String) -> HookTimeout {
        switch self {
        case .codex:
            CodexHookConfiguration.timeout(for: eventName)
        case .geminiCLI:
            .milliseconds(5_000)
        case .claudeCode, .grok, .openCode, .cursor:
            .seconds(5)
        }
    }

    var eventNames: [String] {
        switch self {
        case .codex:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .claudeCode:
            [
                "SessionStart",
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "PostToolUseFailure",
                "PermissionRequest",
                "PermissionDenied",
                "Notification",
                "Elicitation",
                "ElicitationResult",
                "Stop",
                "StopFailure",
                "SessionEnd",
                "SubagentStart",
                "SubagentStop",
            ]
        case .grok:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionEnd", "SubagentStart", "SubagentStop"]
        case .geminiCLI:
            ["SessionStart", "BeforeAgent", "BeforeTool", "AfterTool", "Notification", "AfterAgent", "SessionEnd"]
        case .cursor:
            ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse", "postToolUseFailure", "stop", "sessionEnd"]
        case .openCode:
            []
        }
    }

    func hooksURL(homeDirectoryURL: URL) -> URL {
        switch self {
        case .codex:
            homeDirectoryURL
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json")
        case .claudeCode:
            homeDirectoryURL
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json")
        case .grok:
            homeDirectoryURL
                .appendingPathComponent(".grok/hooks", isDirectory: true)
                .appendingPathComponent("agentsnotch.json")
        case .geminiCLI:
            homeDirectoryURL
                .appendingPathComponent(".gemini", isDirectory: true)
                .appendingPathComponent("settings.json")
        case .openCode:
            homeDirectoryURL
                .appendingPathComponent(".config/opencode/plugins", isDirectory: true)
                .appendingPathComponent("agentsnotch.js")
        case .cursor:
            homeDirectoryURL
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("hooks.json")
        }
    }

    func makeStrategy(homeDirectoryURL: URL) -> any HookInstallStrategy {
        switch self {
        case .cursor:
            CursorHooksInstall(profile: self, homeDirectoryURL: homeDirectoryURL)
        case .openCode:
            OpenCodePluginInstall(homeDirectoryURL: homeDirectoryURL)
        case .codex, .claudeCode, .grok, .geminiCLI:
            GroupedHooksInstall(profile: self, homeDirectoryURL: homeDirectoryURL)
        }
    }
}
