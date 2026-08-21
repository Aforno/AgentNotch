import Foundation

/// Serializes relay copy and hook-config writes across every provider.
/// Shared path `~/.agentnotch/bin/agentnotch-hook` must not be written
/// concurrently.
final class ProviderInstallQueue: @unchecked Sendable {
    static let shared = ProviderInstallQueue()

    private let queue = DispatchQueue(label: "com.afonsoferreira.AgentNotch.provider-install")

    func sync<Result>(_ operation: () throws -> Result) rethrows -> Result {
        try queue.sync(execute: operation)
    }
}
