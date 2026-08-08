import AgentsNotchCore
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case integrations
    #if DEBUG
    case debug
    #endif

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .integrations: "Integrations"
        #if DEBUG
        case .debug: "Debug"
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .integrations: "point.3.connected.trianglepath.dotted"
        #if DEBUG
        case .debug: "hammer"
        #endif
        }
    }
}

struct SettingsView: View {
    let runtime: AppRuntime

    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @AppStorage("displayPreference") private var displayPreference = DisplayPreference.primary.rawValue
    #if DEBUG
    @AppStorage("debugMode") private var debugMode = false
    #endif
    @State private var selection: SettingsPage = .general
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchError: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            ScrollView {
                pageContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 32)
                    .padding(.top, 30)
                    .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 500, idealHeight: 540)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Agents Notch")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 22)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selection = page
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.symbol)
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 18)
                            Text(page.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(selection == page ? Color.accentColor : .primary)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background {
                            if selection == page {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Text("Runs privately on this Mac")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(16)
        }
        .frame(width: 184)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selection {
        case .general:
            generalPage
        case .integrations:
            integrationsPage
        #if DEBUG
        case .debug:
            debugPage
        #endif
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                title: "General",
                subtitle: "Choose how Agents Notch behaves and where it appears.",
                symbol: "slider.horizontal.3"
            )

            SettingsCard(title: "Behavior") {
                PreferenceRow(
                    title: "Launch at login",
                    detail: "Keep agent activity available after you sign in."
                ) {
                    Toggle("Launch at login", isOn: launchBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                PreferenceRow(
                    title: "Animations",
                    detail: "Animate notch expansion and activity changes."
                ) {
                    Toggle("Animations", isOn: $animationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if let launchError {
                    InlineMessage(text: launchError, symbol: "exclamationmark.triangle.fill", color: .red)
                        .padding(.top, 10)
                }
            }

            SettingsCard(title: "Display") {
                PreferenceRow(
                    title: "Show the notch on",
                    detail: "Select the screen Agents Notch should follow."
                ) {
                    Picker("Display", selection: $displayPreference) {
                        ForEach(DisplayPreference.allCases) { preference in
                            Text(preference.title).tag(preference.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }
        }
    }

    private var integrationsPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                title: "Integrations",
                subtitle: "Connect local coding agents to the activity notch.",
                symbol: "point.3.connected.trianglepath.dotted"
            )

            VStack(spacing: 12) {
                integrationCard(runtime.codexIntegration)
                integrationCard(runtime.claudeIntegration)
                integrationCard(runtime.grokIntegration)
            }

            SettingsCard(title: "Local relay") {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(socketColor.opacity(0.14))
                        Circle()
                            .fill(socketColor)
                            .frame(width: 7, height: 7)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Event socket")
                            .font(.system(size: 13, weight: .medium))
                        Text(runtime.socketStatus)
                            .font(.caption)
                            .foregroundStyle(socketColor)
                    }

                    Spacer()

                    Text("~/.agentsnotch/agent.sock")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let error = runtime.socketError {
                    InlineMessage(text: error, symbol: "exclamationmark.triangle.fill", color: .red)
                        .padding(.top, 12)
                }
            }

            InlineMessage(
                text: "Agent events stay on this Mac and are delivered only through the local relay.",
                symbol: "lock.fill",
                color: .secondary
            )
        }
    }

    @ViewBuilder
    private func integrationCard(_ integration: ProviderIntegrationManager) -> some View {
        SettingsCard {
            HStack(spacing: 14) {
                ProviderIconView(provider: integration.provider, size: 21)
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(integration.provider.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    StatusBadge(status: integration.status)
                }

                Spacer(minLength: 16)

                if integration.status == .notInstalled {
                    Button("Install") { integration.install() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    Button {
                        integration.refreshStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Refresh status")
                    .accessibilityLabel("Refresh \(integration.provider.displayName) status")

                    Button("Remove", role: .destructive) { integration.uninstall() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            if integration.status != .notInstalled, let instructions = integration.trustInstructions {
                SettingsDivider()
                    .padding(.vertical, 11)
                InlineMessage(text: instructions, symbol: "info.circle.fill", color: .secondary)
            }

            if let error = integration.lastError {
                InlineMessage(text: error, symbol: "exclamationmark.triangle.fill", color: .red)
                    .padding(.top, 12)
            }
        }
    }

    #if DEBUG
    private var debugPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                title: "Debug",
                subtitle: "Preview agent states and structured activity without a live session.",
                symbol: "hammer"
            )

            SettingsCard(title: "Simulator") {
                PreferenceRow(
                    title: "Enable debug simulator",
                    detail: "Adds temporary sessions to the notch for testing."
                ) {
                    Toggle("Enable debug simulator", isOn: debugModeBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            if debugMode {
                DebugActionCard(title: "Agent states") {
                    DebugAction("Running") { runtime.simulator.simulate(.running) }
                    DebugAction("Editing") { runtime.simulator.simulate(.editing) }
                    DebugAction("Needs approval") { runtime.simulator.simulate(.waitingForUser) }
                    DebugAction("Completed") { runtime.simulator.simulate(.completed) }
                    DebugAction("Failed") { runtime.simulator.simulate(.failed) }
                }

                DebugActionCard(title: "Structured activity") {
                    DebugAction("Plan progress") { runtime.simulator.simulatePlan() }
                    DebugAction("Workflow steps") { runtime.simulator.simulateWorkflow() }
                    DebugAction("Subagent hierarchy") { runtime.simulator.simulateSubagents() }
                    DebugAction("Concurrent demo") { runtime.simulator.runConcurrentDemo() }
                    DebugAction("Clear sessions", role: .destructive) { runtime.simulator.reset() }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: debugMode)
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
                    launchAtLogin = value
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
}
