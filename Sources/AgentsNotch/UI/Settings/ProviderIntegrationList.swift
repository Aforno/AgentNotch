import AgentsNotchCore
import SwiftUI

/// Provider observers in one raised panel, shared by Setup and Settings →
/// Integrations. Setup omits Remove: a first-run window should not offer to
/// undo what it just asked you to install.
struct ProviderIntegrationList: View {
    let runtime: AppRuntime
    var allowsRemove = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(runtime.integrations.enumerated()), id: \.element.provider) { index, integration in
                ProviderIntegrationRow(
                    integration: integration,
                    lastEventAt: runtime.lastEventReceivedAt[integration.provider],
                    allowsRemove: allowsRemove
                )
                if index < runtime.integrations.count - 1 {
                    NotchHairline(leadingInset: 38)
                }
            }
        }
        .padding(.horizontal, 14)
        .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)
    }
}

private struct ProviderIntegrationRow: View {
    let integration: ProviderIntegrationManager
    let lastEventAt: Date?
    let allowsRemove: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderIconView(provider: integration.provider, size: 20)
                .foregroundStyle(NotchWindowPalette.primaryText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                ProviderStatusLine(status: integration.status, lastEventAt: lastEventAt)

                if let instructions = integration.trustInstructions {
                    Text(instructions)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = integration.lastError {
                    Text(error)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.failure)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            actions
        }
        .controlSize(.small)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var actions: some View {
        if integration.status.canInstall {
            Button(integration.status == .notInstalled ? "Install" : "Retry") {
                Task { await integration.install() }
            }
            .buttonStyle(NotchPillButtonStyle())
            .disabled(integration.isPerformingMaintenance)
        } else {
            HStack(spacing: 6) {
                Button {
                    integration.refreshStatus(hasReceivedEvent: lastEventAt != nil)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(NotchIconButtonStyle())
                .help("Refresh status")
                .accessibilityLabel("Refresh \(integration.provider.displayName) status")

                if allowsRemove {
                    Button("Remove", role: .destructive) {
                        Task { await integration.uninstall() }
                    }
                    .buttonStyle(NotchPillButtonStyle(destructive: true))
                }
            }
            .disabled(integration.isPerformingMaintenance)
        }
    }
}

/// "● Connected · last event 2m ago". The dot uses the state hues so a glance
/// down the list shows which observers are live.
private struct ProviderStatusLine: View {
    let status: ProviderIntegrationStatus
    let lastEventAt: Date?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status == .awaitingFirstEvent ? "Installed, no events yet" : status.title)
                .foregroundStyle(status == .notInstalled ? NotchWindowPalette.tertiaryText : color)
            if status == .connected, let lastEventAt {
                Text("·").foregroundStyle(NotchWindowPalette.quaternaryText)
                Text("last event")
                    .foregroundStyle(NotchWindowPalette.tertiaryText)
                ElapsedLabel(since: lastEventAt, phrased: true)
            }
        }
        .font(NotchWindowFont.footnote)
        .lineLimit(1)
    }

    private var color: Color {
        switch status {
        case .notInstalled: NotchWindowPalette.quaternaryText
        case .awaitingFirstEvent: NotchWindowPalette.attention
        case .connected: NotchWindowPalette.success
        case .unavailable: NotchWindowPalette.failure
        }
    }
}
