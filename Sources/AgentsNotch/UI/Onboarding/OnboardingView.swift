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
                    Text("Install one or more local observers, confirm the relay, then leave the notch collapsed until an agent needs input.")
                        .font(NotchWindowFont.body)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                providerRow(runtime.codexIntegration)
                NotchHairline(leadingInset: 42)
                providerRow(runtime.claudeIntegration)
                NotchHairline(leadingInset: 42)
                providerRow(runtime.grokIntegration)
                NotchHairline(leadingInset: 42)
                providerRow(runtime.geminiIntegration)
            }
            .padding(.horizontal, 14)
            .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)

            HStack(spacing: 8) {
                Image(systemName: runtime.socketStatus == "Listening" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(runtime.socketStatus == "Listening" ? .green : .orange)
                Text("Local relay: \(runtime.socketStatus)")
                    .font(NotchWindowFont.bodyEmphasis)
                    .foregroundStyle(NotchWindowPalette.primaryText)
                Spacer()
                Text("No source code or prompts leave this Mac.")
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }

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
        .frame(width: 640, height: 480)
        .foregroundStyle(NotchWindowPalette.primaryText)
        .deepBlackWindowSurface()
    }

    private func providerRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(spacing: 12) {
            ProviderIconView(provider: integration.provider, size: 22)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                Text(providerDetail(integration))
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if integration.status.canInstall {
                Button("Install") { integration.install() }
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

    private func providerDetail(_ integration: ProviderIntegrationManager) -> String {
        if let lastEvent = runtime.lastEventReceivedAt[integration.provider] {
            return "Connected · last event \(lastEvent.formatted(.relative(presentation: .named)))"
        }
        if let trust = integration.trustInstructions {
            return trust
        }
        if integration.status == .awaitingFirstEvent {
            return "Installed. Waiting for the first provider event."
        }
        return integration.status.title
    }
}
