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
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false
    @AppStorage("globalActivityShortcut") private var globalActivityShortcut = GlobalActivityShortcut.off.rawValue
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
        .onChange(of: globalActivityShortcut) { _, value in runtime.updateGlobalShortcut(value) }
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
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "General",
                    detail: "Control how Agents Notch starts, alerts, and stores local history."
                )

                ApplicationSettingsSection(
                    launchAtLogin: launchBinding,
                    animationsEnabled: $animationsEnabled,
                    notchEnabled: $notchEnabled,
                    showVirtualNotch: $showVirtualNotch,
                    automaticallyCheckForUpdates: $automaticallyCheckForUpdates,
                    displayPreference: $displayPreference,
                    globalActivityShortcut: $globalActivityShortcut,
                    updates: runtime.updates
                )
                AttentionSettingsSection(
                    notificationsEnabled: notificationBinding,
                    soundEnabled: $attentionNotificationSoundEnabled,
                    failureNotificationsEnabled: $failureNotificationsEnabled
                )
                PrivacySettingsSection(privacyModeEnabled: $privacyModeEnabled)
                HistorySettingsSection(
                    retentionDays: $historyRetentionDays,
                    hasCompletedSessions: !runtime.activity.recentSessions.isEmpty,
                    openActivityCenter: runtime.openActivityCenter,
                    openOnboarding: runtime.openOnboarding,
                    requestClearHistory: { confirmsClearHistory = true }
                )

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
    private func integrationRow(_ integration: ProviderIntegrationManager) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderIconView(provider: integration.provider, size: 20)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(integration.provider.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))

                if showsStatus(integration.status) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
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

                Button("Remove", role: .destructive) {
                    integration.uninstall()
                }
                .buttonStyle(NotchPillButtonStyle(destructive: true))
            }
        }
        .controlSize(.small)
        .padding(.vertical, 9)
    }

    #if DEBUG
    private var debugPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "Debug",
                    detail: "Preview agent states without a live session."
                )

                SettingsSection(title: "Simulator") {
                    SettingsToggleRow(
                        title: "Enable debug simulator",
                        detail: "Inject synthetic agent activity into the notch and Activity Center.",
                        isOn: debugModeBinding
                    )
                }

                if debugMode {
                    SettingsSection(title: "Agent States") {
                        SettingsControlRow(
                            title: "Inject state",
                            detail: "Push a single simulated agent into the selected state."
                        ) {
                            HStack(spacing: 8) {
                                Button("Running") { runtime.simulator.simulate(.running) }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Editing") { runtime.simulator.simulate(.editing) }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Needs Approval") { runtime.simulator.simulate(.waitingForUser) }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Completed") { runtime.simulator.simulate(.completed) }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Failed") { runtime.simulator.simulate(.failed) }
                                    .buttonStyle(NotchPillButtonStyle())
                            }
                        }
                    }

                    SettingsSection(title: "Structured Activity") {
                        SettingsControlRow(
                            title: "Inject activity",
                            detail: "Preview plans, workflows, and concurrent agent demos."
                        ) {
                            HStack(spacing: 8) {
                                Button("Plan") { runtime.simulator.simulatePlan() }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Workflow") { runtime.simulator.simulateWorkflow() }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Subagents") { runtime.simulator.simulateSubagents() }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Concurrent") { runtime.simulator.runConcurrentDemo() }
                                    .buttonStyle(NotchPillButtonStyle())
                                Button("Clear", role: .destructive) { runtime.simulator.reset() }
                                    .buttonStyle(NotchPillButtonStyle(destructive: true))
                            }
                        }
                    }
                }
            }
            .settingsPanePadding()
        }
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

    private func showsStatus(_ status: ProviderIntegrationStatus) -> Bool {
        switch status {
        case .unavailable: true
        case .notInstalled, .awaitingFirstEvent, .connected: false
        }
    }
}
