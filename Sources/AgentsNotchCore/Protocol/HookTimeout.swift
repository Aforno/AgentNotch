import Foundation

/// Unit attached to a provider hook timeout. Gemini documents milliseconds;
/// Codex, Claude Code, Grok, and Cursor document seconds.
public enum HookTimeoutUnit: String, Sendable, Equatable {
    case seconds
    case milliseconds
}

/// A timeout that cannot be a bare integer. JSON still stores the numeric
/// value the vendor expects; the unit travels with the number.
public enum HookTimeout: Equatable, Sendable {
    case seconds(Int)
    case milliseconds(Int)

    public var jsonValue: Int {
        switch self {
        case .seconds(let value), .milliseconds(let value):
            value
        }
    }

    public var unit: HookTimeoutUnit {
        switch self {
        case .seconds:
            .seconds
        case .milliseconds:
            .milliseconds
        }
    }
}
