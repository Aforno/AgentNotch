import Foundation

public struct AgentProvider: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.lowercased()
    }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude"
        case .grok: "Grok"
        case .openCode: "OpenCode"
        case .geminiCLI: "Gemini"
        case .cursor: "Cursor"
        default: rawValue.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    public static let codex = AgentProvider(rawValue: "codex")
    public static let claudeCode = AgentProvider(rawValue: "claude-code")
    public static let grok = AgentProvider(rawValue: "grok")
    public static let openCode = AgentProvider(rawValue: "opencode")
    public static let geminiCLI = AgentProvider(rawValue: "gemini-cli")
    public static let cursor = AgentProvider(rawValue: "cursor")
    public static let simulator = AgentProvider(rawValue: "simulator")
}
