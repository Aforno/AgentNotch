import AgentsNotchCore
import SwiftUI

struct SettingsView: View {
    let runtime: AppRuntime

    @AppStorage("animationsEnabled") private var animationsEnabled = true
    @AppStorage("displayPreference") private var displayPreference = DisplayPreference.primary.rawValue
    @AppStorage("attentionNotificationsEnabled") private var attentionNotificationsEnabled = false
    @AppStorage("attentionNotificationSoundEnabled") private var attentionNotificationSoundEnabled = false
    @AppStorage("failureNotificationsEnabled") private var failureNotificationsEnabled = false
    @AppStorage("historyRetentionDays") private var historyRetentionDays = 30
    @AppStorage("notchEnabled") private var notchEnabled = true
    @AppStorage("showVirtualNotch") private var showVirtualNotch = false
    @AppStorage("automaticallyCheckForUpdates") private var automaticallyCheckForUpdates = false
    #if DEBUG
    @AppStorage("debugMode") private var debugMode = false
    #endif
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var launchError: String?
    @State private var notificationError: String?
    @State private var confirmsClearHistory = false

    var body: some View {
        ZStack {
            NotchWindowPalette.background.ignoresSafeArea()

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
        }
        .frame(width: 580, height: 560)
        .groupBoxStyle(NotchSettingsGroupBoxStyle())
        .deepBlackWindowSurface()
        .onAppear {
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
        .onChange(of: historyRetentionDays) { _, days in
            runtime.applyHistoryRetention(days: days)
        }
        .onChange(of: automaticallyCheckForUpdates) { _, enabled in
            if enabled { runtime.updates.checkAutomaticallyIfNeeded() }
        }
        .onChange(of: displayPreference) { _, _ in runtime.refreshNotchSurface() }
        .onChange(of: notchEnabled) { _, _ in runtime.refreshNotchSurface() }
        .onChange(of: showVirtualNotch) { _, _ in runtime.refreshNotchSurface() }
    }

    private var generalPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsHeading(
                    title: "General",
                    detail: "Control how Agents Notch starts, alerts, and stores local history."
                )

                GroupBox("Application") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Launch Agents Notch at login", isOn: launchBinding)
                        Toggle("Animate notch transitions", isOn: $animationsEnabled)
                        Toggle("Show notch surface", isOn: $notchEnabled)
                        Toggle("Show a virtual notch on displays without hardware", isOn: $showVirtualNotch)
                        Toggle("Automatically check GitHub for updates", isOn: $automaticallyCheckForUpdates)

                        HStack {
                            Text("Show the notch on:")
                            Spacer()
                            Picker("Show the notch on", selection: $displayPreference) {
                                ForEach(DisplayPreference.allCases) { preference in
                                    Text(preference.title).tag(preference.rawValue)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190)
                        }
                        HStack {
                            Text("Version \(runtime.updates.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            updateControl
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Attention") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show macOS notifications when an agent needs input", isOn: notificationBinding)
                        Toggle("Play notification sound", isOn: $attentionNotificationSoundEnabled)
                            .disabled(!attentionNotificationsEnabled)
                        Toggle("Also notify when an agent fails", isOn: $failureNotificationsEnabled)
                            .disabled(!attentionNotificationsEnabled)
                        Text("Routine activity and completions remain collapsed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Local History") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Keep completed sessions")
                            Spacer()
                            Picker("Keep completed sessions", selection: $historyRetentionDays) {
                                Text("7 days").tag(7)
                                Text("30 days").tag(30)
                                Text("90 days").tag(90)
                                Text("1 year").tag(365)
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        HStack {
                            Button("Open Activity Center") { runtime.openActivityCenter() }
                            Button("Show Setup") { runtime.openOnboarding() }
                            Spacer()
                            Button("Clear Completed History", role: .destructive) {
                                confirmsClearHistory = true
                            }
                            .disabled(runtime.activity.recentSessions.isEmpty)
                        }
                    }
                    .padding(.top, 4)
                }

                if let launchError {
                    SettingsMessage(text: launchError, symbol: "exclamationmark.triangle.fill", color: .red)
                }
                if let notificationError {
                    SettingsMessage(text: notificationError, symbol: "bell.slash.fill", color: .orange)
                }
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
        .confirmationDialog("Clear completed session history?", isPresented: $confirmsClearHistory) {
            Button("Clear History", role: .destructive) { runtime.clearHistory() }
        } message: {
            Text("Active and waiting sessions will be kept.")
        }
    }

    private var integrationsPane: some View {
        ScrollView {
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
                Divider()
                    .padding(.leading, 34)
                integrationRow(runtime.geminiIntegration)
            }
            .padding(.horizontal, 14)
            .notchPanel()

            VStack(alignment: .leading, spacing: 8) {
                Text("Local Relay")
                    .font(.system(.headline, design: .monospaced).weight(.bold))

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
            .padding(14)
            .notchPanel()

            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
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

                if let lastEvent = runtime.lastEventReceivedAt[integration.provider] {
                    Text("Last event \(lastEvent.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if integration.status.canInstall {
                Button(integration.status == .notInstalled ? "Install" : "Retry") {
                    integration.install()
                }
            } else {
                selfTestControl(for: integration.provider)

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

    @ViewBuilder
    private func selfTestControl(for provider: AgentProvider) -> some View {
        switch runtime.selfTestStatuses[provider] ?? .idle {
        case .idle:
            Button("Test") { runtime.runSelfTest(for: provider) }
        case .running:
            ProgressView().controlSize(.small).frame(width: 34)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Installed relay delivered a local test event")
        case let .failed(message):
            Button("Retry") { runtime.runSelfTest(for: provider) }
                .help(message)
        }
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
        .background(NotchWindowPalette.background)
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

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { attentionNotificationsEnabled },
            set: { enabled in
                if !enabled {
                    attentionNotificationsEnabled = false
                    notificationError = nil
                    return
                }
                Task { @MainActor in
                    let granted = await runtime.notifications.setEnabled(true)
                    attentionNotificationsEnabled = granted
                    notificationError = granted
                        ? nil
                        : "Notifications are disabled in System Settings. The notch will still show attention states."
                }
            }
        )
    }

    private var socketColor: Color {
        runtime.socketStatus == "Listening" ? .green : .orange
    }

    @ViewBuilder
    private var updateControl: some View {
        switch runtime.updates.state {
        case .idle:
            Button("Check for Updates") { Task { await runtime.updates.check() } }
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .noRelease:
            Label("No releases yet", systemImage: "shippingbox")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .available(version, _):
            Button("Download \(version)") { runtime.updates.openAvailableRelease() }
        case let .failed(message):
            Button("Retry") { Task { await runtime.updates.check() } }
                .help(message)
        }
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
            Text(title.uppercased())
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .tracking(-0.5)
            Text(detail)
                .font(.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
        }
    }
}

private struct NotchSettingsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            configuration.label
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.74))

            Rectangle()
                .fill(NotchWindowPalette.border)
                .frame(height: 1)

            configuration.content
        }
        .padding(14)
        .notchPanel()
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
