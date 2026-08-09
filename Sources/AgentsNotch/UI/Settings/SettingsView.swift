import AgentsNotchCore
import SwiftUI

struct SettingsView: View {
    let runtime: AppRuntime

    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @AppStorage("displayPreference") private var displayPreference = DisplayPreference.primary.rawValue
    #if DEBUG
    @AppStorage("debugMode") private var debugMode = false
    #endif
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchError: String?

    var body: some View {
        TabView {
            generalPane
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            integrationsPane
                .tabItem {
                    Label("Integrations", systemImage: "point.3.connected.trianglepath.dotted")
                }

            #if DEBUG
            debugPane
                .tabItem {
                    Label("Debug", systemImage: "hammer")
                }
            #endif
        }
        .frame(width: 540, height: 440)
        .onAppear {
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading(
                title: "General",
                detail: "Control how Agents Notch starts and appears."
            )

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch Agents Notch at login", isOn: launchBinding)
                Toggle("Animate notch transitions", isOn: $animationsEnabled)
            }

            Divider()

            HStack {
                Text("Show the notch on:")
                Spacer()
                Picker("Show the notch on", selection: $displayPreference) {
                    ForEach(DisplayPreference.allCases) { preference in
                        Text(preference.title).tag(preference.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            if let launchError {
                SettingsMessage(
                    text: launchError,
                    symbol: "exclamationmark.triangle.fill",
                    color: .red
                )
            }

            Spacer()
        }
        .settingsPanePadding()
    }

    private var integrationsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsHeading(
                title: "Integrations",
                detail: "Connect local coding agents to Agents Notch."
            )

            VStack(spacing: 0) {
                integrationRow(runtime.codexIntegration)
                Divider()
                    .padding(.leading, 34)
                integrationRow(runtime.claudeIntegration)
                Divider()
                    .padding(.leading, 34)
                integrationRow(runtime.grokIntegration)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Relay")
                    .font(.headline)

                HStack(spacing: 8) {
                    Circle()
                        .fill(socketColor)
                        .frame(width: 7, height: 7)

                    Text(runtime.socketStatus)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("~/.agentsnotch/agent.sock")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let error = runtime.socketError {
                    SettingsMessage(
                        text: error,
                        symbol: "exclamationmark.triangle.fill",
                        color: .red
                    )
                } else {
                    Text("Events stay on this Mac and are delivered through the local socket.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = runtime.persistenceError {
                    SettingsMessage(
                        text: error,
                        symbol: "externaldrive.badge.exclamationmark",
                        color: .orange
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .settingsPanePadding()
    }

    @ViewBuilder
    private func integrationRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderIconView(provider: integration.provider, size: 20)
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .fontWeight(.medium)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor(for: integration.status))
                        .frame(width: 6, height: 6)
                    Text(integration.status.title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if integration.status != .notInstalled,
                   let instructions = integration.trustInstructions {
                    Text(instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = integration.lastError {
                    Text(error)
                        .font(.caption)
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
            } else {
                Button {
                    integration.refreshStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh status")
                .accessibilityLabel("Refresh \(integration.provider.displayName) status")

                Button("Remove", role: .destructive) {
                    integration.uninstall()
                }
            }
        }
        .controlSize(.small)
        .padding(.vertical, 8)
    }

    #if DEBUG
    private var debugPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading(
                title: "Debug",
                detail: "Preview agent states without a live session."
            )

            Toggle("Enable debug simulator", isOn: debugModeBinding)

            if debugMode {
                Divider()

                SettingsButtonGroup(title: "Agent States") {
                    Button("Running") { runtime.simulator.simulate(.running) }
                    Button("Editing") { runtime.simulator.simulate(.editing) }
                    Button("Needs Approval") { runtime.simulator.simulate(.waitingForUser) }
                    Button("Completed") { runtime.simulator.simulate(.completed) }
                    Button("Failed") { runtime.simulator.simulate(.failed) }
                }

                SettingsButtonGroup(title: "Structured Activity") {
                    Button("Plan") { runtime.simulator.simulatePlan() }
                    Button("Workflow") { runtime.simulator.simulateWorkflow() }
                    Button("Subagents") { runtime.simulator.simulateSubagents() }
                    Button("Concurrent") { runtime.simulator.runConcurrentDemo() }
                    Button("Clear", role: .destructive) { runtime.simulator.reset() }
                }
            }

            Spacer()
        }
        .settingsPanePadding()
    }

    private var debugModeBinding: Binding<Bool> {
        Binding(
            get: { debugMode },
            set: { enabled in
                debugMode = enabled
                if !enabled {
                    runtime.simulator.reset()
                }
            }
        )
    }
    #endif

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { value in
                do {
                    try LaunchAtLoginService.setEnabled(value)
                    launchAtLogin = LaunchAtLoginService.isEnabled
                    launchError = nil
                } catch {
                    launchAtLogin = LaunchAtLoginService.isEnabled
                    launchError = error.localizedDescription
                }
            }
        )
    }

    private var socketColor: Color {
        runtime.socketStatus == "Listening" ? .green : .orange
    }

    private func statusColor(for status: ProviderIntegrationStatus) -> Color {
        switch status {
        case .ready: .green
        case .installedNeedsTrust: .orange
        case .notInstalled: .secondary
        case .unavailable: .red
        }
    }
}

private struct SettingsHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsMessage: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

#if DEBUG
private struct SettingsButtonGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(spacing: 8) {
                content
            }
            .controlSize(.small)
        }
    }
}
#endif

private extension View {
    func settingsPanePadding() -> some View {
        padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
    }
}
