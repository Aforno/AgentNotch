import SwiftUI

struct IntegrationSettingsPane: View {
    let runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotchWindowMetrics.sectionSpacing) {
                SettingsHeading(
                    title: "Integrations",
                    detail: "Install a local observer for each agent you use."
                )
                runtimeHealthMessages
                VStack(spacing: 0) {
                    ForEach(Array(runtime.integrations.enumerated()), id: \.element.provider) { index, integration in
                        integrationRow(integration)
                        if index < runtime.integrations.count - 1 {
                            NotchHairline(leadingInset: 42)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }

    @ViewBuilder
    private var runtimeHealthMessages: some View {
        if runtime.socketError != nil
            || runtime.persistenceError != nil
            || runtime.persistenceRecoveryNotice != nil
            || runtime.activity.protocolMismatchDetected
        {
            RuntimeHealthMessages(
                socketError: runtime.socketError,
                persistenceError: runtime.persistenceError,
                persistenceRecoveryNotice: runtime.persistenceRecoveryNotice,
                protocolMismatchDetected: runtime.activity.protocolMismatchDetected
            )
        }
    }

    private func integrationRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderIconView(provider: integration.provider, size: 20)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .accessibilityLabel("\(integration.provider.displayName), \(integration.status.title)")
                if let instructions = integration.trustInstructions {
                    Text(instructions)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = integration.lastError {
                    Text(error)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            if integration.status.canInstall {
                Button(integration.status == .notInstalled ? "Install" : "Retry") {
                    Task { await integration.install() }
                }
                .buttonStyle(NotchPillButtonStyle())
                .disabled(integration.isPerformingMaintenance)
            } else {
                Button {
                    integration.refreshStatus(
                        hasReceivedEvent: runtime.lastEventReceivedAt[integration.provider] != nil
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(NotchIconButtonStyle())
                .help("Refresh status")
                .accessibilityLabel("Refresh \(integration.provider.displayName) status")
                .disabled(integration.isPerformingMaintenance)
                Button("Remove", role: .destructive) {
                    Task { await integration.uninstall() }
                }
                .buttonStyle(NotchPillButtonStyle(destructive: true))
                .disabled(integration.isPerformingMaintenance)
            }
        }
        .controlSize(.small)
        .padding(.vertical, 9)
    }
}
