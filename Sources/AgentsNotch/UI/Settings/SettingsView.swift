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
    @State private var pane = Pane.general

    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case integrations
        #if DEBUG
        case debug
        #endif

        var id: String { rawValue }

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
            case .general: "gearshape"
            case .integrations: "point.3.connected.trianglepath.dotted"
            #if DEBUG
            case .debug: "hammer"
            #endif
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            paneSelector

            NotchHairline()

            Group {
                switch pane {
                case .general: generalPane
                case .integrations: integrationsPane
                #if DEBUG
                case .debug: debugPane
                #endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(NotchWindowPalette.primaryText)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 480, idealHeight: 560)
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

    private var paneSelector: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases) { candidate in
                Button {
                    pane = candidate
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 10, weight: .medium))
                        Text(candidate.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(pane == candidate ? 0.92 : 0.5))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        pane == candidate ? NotchWindowPalette.raisedStrong : .clear,
                        in: RoundedRectangle(cornerRadius: NotchWindowMetrics.controlRadius, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(pane == candidate ? .isSelected : [])
            }

            Spacer()
        }
        .padding(.horizontal, NotchWindowMetrics.contentInset)
        .padding(.vertical, 10)
        .background(NotchWindowPalette.background)
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
                                .font(NotchWindowFont.caption)
                                .foregroundStyle(NotchWindowPalette.secondaryText)
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
                            .font(NotchWindowFont.caption)
                            .foregroundStyle(NotchWindowPalette.secondaryText)
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
            VStack(alignment: .leading, spacing: NotchWindowMetrics.sectionSpacing) {
            SettingsHeading(
                title: "Integrations",
                detail: "Connect local coding agents to Agents Notch."
            )

            VStack(spacing: 0) {
                integrationRow(runtime.codexIntegration)
                NotchHairline(leadingInset: 42)
                integrationRow(runtime.claudeIntegration)
                NotchHairline(leadingInset: 42)
                integrationRow(runtime.grokIntegration)
                NotchHairline(leadingInset: 42)
                integrationRow(runtime.geminiIntegration)
            }
            .padding(.horizontal, 14)
            .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)

            VStack(alignment: .leading, spacing: 10) {
                NotchSectionLabel(title: "Local Relay")

                HStack(spacing: 8) {
                    Circle()
                        .fill(socketColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: socketColor.opacity(0.5), radius: 3)

                    Text(runtime.socketStatus)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)

                    Spacer()

                    Text("~/.agentsnotch/agent.sock")
                        .font(NotchWindowFont.mono)
                        .foregroundStyle(NotchWindowPalette.tertiaryText)
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
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                }

                if let error = runtime.persistenceError {
                    SettingsMessage(
                        text: error,
                        symbol: "externaldrive.badge.exclamationmark",
                        color: .orange
                    )
                }
            }
            .padding(NotchWindowMetrics.rowInset)
            .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)

            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }

    @ViewBuilder
    private func integrationRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProviderIconView(provider: integration.provider, size: 20)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor(for: integration.status))
                        .frame(width: 6, height: 6)
                    Text(integration.status.title)
                }
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)

                if integration.status != .notInstalled,
                   let instructions = integration.trustInstructions {
                    Text(instructions)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = integration.lastError {
                    Text(error)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let lastEvent = runtime.lastEventReceivedAt[integration.provider] {
                    Text("Last event \(lastEvent.formatted(.relative(presentation: .named)))")
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
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
        .padding(.vertical, 9)
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
                NotchHairline()

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
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(NotchWindowFont.display)
                .foregroundStyle(.white.opacity(0.92))
            Text(detail)
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
        }
    }
}

private struct NotchSettingsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(NotchWindowFont.sectionLabel)
                .foregroundStyle(.white.opacity(0.74))

            configuration.content
        }
        .padding(NotchWindowMetrics.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .notchPanel(cornerRadius: NotchWindowMetrics.cardRadius)
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
                .font(NotchWindowFont.sectionLabel)
                .foregroundStyle(.white.opacity(0.74))
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
        padding(.horizontal, NotchWindowMetrics.contentInset)
            .padding(.top, 18)
            .padding(.bottom, 16)
    }
}
