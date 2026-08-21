import SwiftUI

struct IntegrationSettingsPane: View {
    let runtime: AppRuntime

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotchWindowMetrics.sectionSpacing) {
                SettingsHeading(
                    title: "Integrations",
                    detail: "Connect local coding agents to Agent Notch."
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
        {
            RuntimeHealthMessages(
                socketError: runtime.socketError,
                persistenceError: runtime.persistenceError,
                persistenceRecoveryNotice: runtime.persistenceRecoveryNotice
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
                if case .unavailable = integration.status {
                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(integration.status.title)
                    }
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                }
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
                Button(integration.status == .notInstalled ? "Install" : "Retry") { integration.install() }
                    .buttonStyle(NotchPillButtonStyle())
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
                Button("Remove", role: .destructive) { integration.uninstall() }
                    .buttonStyle(NotchPillButtonStyle(destructive: true))
            }
        }
        .controlSize(.small)
        .padding(.vertical, 9)
    }
}
