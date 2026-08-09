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
                        .font(.title2.weight(.semibold))
                    Text("Install one or more local observers, confirm the relay, then leave the notch collapsed until an agent needs input.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                providerRow(runtime.codexIntegration)
                Divider().padding(.leading, 42)
                providerRow(runtime.claudeIntegration)
                Divider().padding(.leading, 42)
                providerRow(runtime.grokIntegration)
                Divider().padding(.leading, 42)
                providerRow(runtime.geminiIntegration)
            }
            .padding(.horizontal, 14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                Image(systemName: runtime.socketStatus == "Listening" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(runtime.socketStatus == "Listening" ? .green : .orange)
                Text("Local relay: \(runtime.socketStatus)")
                    .fontWeight(.medium)
                Spacer()
                Text("No source code or prompts leave this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Open Activity Center") { runtime.openActivityCenter() }
                Spacer()
                Button("Finish") {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640, height: 480)
    }

    private func providerRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(spacing: 12) {
            ProviderIconView(provider: integration.provider, size: 22)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .fontWeight(.medium)
                Text(providerDetail(integration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if integration.status.canInstall {
                Button("Install") { integration.install() }
            } else {
                selfTestButton(for: integration.provider)
                Button {
                    integration.refreshStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh status")
            }
        }
        .controlSize(.small)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func selfTestButton(for provider: AgentProvider) -> some View {
        switch runtime.selfTestStatuses[provider] ?? .idle {
        case .idle:
            Button("Test") { runtime.runSelfTest(for: provider) }
        case .running:
            ProgressView().controlSize(.small).frame(width: 48)
        case .passed:
            Label("Relay verified", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Button("Retry") { runtime.runSelfTest(for: provider) }
                .help(message)
        }
    }

    private func providerDetail(_ integration: ProviderIntegrationManager) -> String {
        if let lastEvent = runtime.lastEventReceivedAt[integration.provider] {
            return "Last provider event received \(lastEvent.formatted(.relative(presentation: .named)))"
        }
        if integration.status == .installedNeedsTrust {
            return "Installed. Review and trust the hooks inside the provider once."
        }
        return integration.status.title
    }
}
