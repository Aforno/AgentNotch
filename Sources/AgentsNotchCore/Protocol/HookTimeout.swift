import Foundation

/// A timeout that cannot be a bare integer. JSON still stores the numeric
/// value the vendor expects; Gemini uses milliseconds, the others use seconds.
public enum HookTimeout: Equatable, Sendable {
    case seconds(Int)
    case milliseconds(Int)

    public var jsonValue: Int {
        switch self {
        case .seconds(let value), .milliseconds(let value):
            value
        }
    }
}
