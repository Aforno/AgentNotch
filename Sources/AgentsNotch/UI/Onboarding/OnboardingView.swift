import AgentsNotchCore
import SwiftUI

struct OnboardingView: View {
    let runtime: AppRuntime
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Agents should find you—not interrupt you")
                        .font(NotchWindowFont.title)
                        .foregroundStyle(NotchWindowPalette.primaryText)
                    Text("Install one or more local observers, then leave the notch collapsed until an agent needs input.")
                        .font(NotchWindowFont.body)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(runtime.integrations.enumerated()), id: \.element.provider) { index, integration in
                    providerRow(integration)
                    if index < runtime.integrations.count - 1 {
                        NotchHairline(leadingInset: 42)
                    }
                }
            }
            .padding(.horizontal, 14)
            .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)

            Spacer()

            HStack {
                Button("Open Activity Center") { runtime.openActivityCenter() }
                    .buttonStyle(NotchPillButtonStyle())
                Spacer()
                Button("Finish") {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onDone()
                }
                .buttonStyle(NotchPillButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 560)
        .foregroundStyle(NotchWindowPalette.primaryText)
        .deepBlackWindowSurface()
    }

    private func providerRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderIconView(provider: integration.provider, size: 22)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))

                if case let .unavailable(message) = integration.status {
                    Text(message)
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
                Button(integration.status == .notInstalled ? "Install" : "Retry") {
                    integration.install()
                }
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
            }
        }
        .controlSize(.small)
        .padding(.vertical, 11)
    }
}
