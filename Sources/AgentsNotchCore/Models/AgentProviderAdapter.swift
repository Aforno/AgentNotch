import Foundation

@MainActor
public protocol AgentProviderAdapter: AnyObject {
    var provider: AgentProvider { get }
    var statusDescription: String { get }

    func startMonitoring() async throws
    func stopMonitoring() async
    func discoverSessions() async throws -> [AgentSession]
}
