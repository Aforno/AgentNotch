import AgentsNotchCore
import Foundation

@MainActor
final class HookProviderAdapter: AgentProviderAdapter {
    let provider: AgentProvider
    let integration: ProviderIntegrationManager

    init(integration: ProviderIntegrationManager) {
        provider = integration.provider
        self.integration = integration
    }

    var statusDescription: String { integration.status.title }

    func startMonitoring() async throws {
        integration.prepareForMonitoring()
    }

    func stopMonitoring() async {
        // Hooks are push-based; there is no process subscription to tear down.
        // Stale actives are reconciled on launch via
        // AgentActivityService.reconcileUnverifiedActiveSessions().
    }

    func discoverSessions() async throws -> [AgentSession] {
        // Hooks are event-driven; no transcript polling or filesystem scan is used.
        // Cold-start recovery lives in AgentActivityService: dead origin PIDs
        // complete immediately, remaining restored runners become `.unknown`
        // for a reconnect grace period instead of inventing completion.
        []
    }
}
