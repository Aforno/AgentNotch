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
        await integration.prepareForMonitoring()
    }

    func stopMonitoring() async {
        // Hooks are push-based; there is no process subscription to tear down.
        // Stale actives are reconciled on launch via
        // AgentActivityService.reconcileUnverifiedActiveSessions().
    }

    func discoverSessions() async throws -> [AgentSession] {
        // Hooks are push-only. Do not invent live sessions from disk.
        // Titles, hierarchy, and cold-start evidence are launch-time reads in
        // CodexSessionTitleResolver, GrokSessionContextResolver, and the
        // restorers — never a scan that creates sessions here.
        []
    }
}
