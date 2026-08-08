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
        // AgentActivityService.completeUnverifiedActiveSessions().
    }

    func discoverSessions() async throws -> [AgentSession] {
        // Hooks are event-driven; no transcript polling or filesystem scan is used.
        // Live process reconciliation is not available, so AppRuntime completes
        // restored active sessions on start instead of merging a discovered set.
        []
    }
}
