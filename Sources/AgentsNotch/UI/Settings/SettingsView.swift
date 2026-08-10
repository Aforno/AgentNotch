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
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "General",
                    detail: "Control how Agents Notch starts, alerts, and stores local history."
                )

                SettingsSection(title: "Application") {
                    SettingsToggleRow(
                        title: "Launch at login",
                        detail: "Start Agents Notch automatically when you sign in to this Mac.",
                        isOn: launchBinding
                    )
                    SettingsToggleRow(
                        title: "Animate notch transitions",
                        detail: "Smooth open, close, and content changes on the notch surface.",
                        isOn: $animationsEnabled
                    )
                    SettingsToggleRow(
                        title: "Show notch surface",
                        detail: "Display live agent activity on the hardware or virtual notch.",
                        isOn: $notchEnabled
                    )
                    SettingsToggleRow(
                        title: "Virtual notch",
                        detail: "Show a virtual notch on displays without hardware cutouts.",
                        isOn: $showVirtualNotch
                    )
                    SettingsToggleRow(
                        title: "Provider update checks",
                        detail: "Automatically check GitHub for newer Agents Notch releases.",
                        isOn: $automaticallyCheckForUpdates
                    )
                    SettingsMenuRow(
                        title: "Show the notch on",
                        detail: "Choose which display hosts the notch surface.",
                        selection: $displayPreference,
                        options: DisplayPreference.allCases.map { ($0.rawValue, $0.title) }
                    )
                    SettingsControlRow(title: "Version", detail: "Current app version and update status.") {
                        HStack(spacing: 8) {
                            Text(runtime.updates.currentVersion)
                                .font(NotchWindowFont.control)
                                .foregroundStyle(NotchWindowPalette.secondaryText)
                            updateControl
                        }
                    }
                }

                SettingsSection(title: "Attention") {
                    SettingsToggleRow(
                        title: "Attention notifications",
                        detail: "Show macOS notifications when an agent needs input.",
                        isOn: notificationBinding
                    )
                    SettingsToggleRow(
                        title: "Notification sound",
                        detail: "Play the system notification sound with attention alerts.",
                        isOn: $attentionNotificationSoundEnabled
                    )
                    .disabled(!attentionNotificationsEnabled)
                    .opacity(attentionNotificationsEnabled ? 1 : 0.45)
                    SettingsToggleRow(
                        title: "Failure notifications",
                        detail: "Also notify when an agent fails. Routine activity stays collapsed.",
                        isOn: $failureNotificationsEnabled
                    )
                    .disabled(!attentionNotificationsEnabled)
                    .opacity(attentionNotificationsEnabled ? 1 : 0.45)
                }

                SettingsSection(title: "Local History") {
                    SettingsMenuRow(
                        title: "Keep completed sessions",
                        detail: "How long finished sessions remain in Activity Center.",
                        selection: $historyRetentionDays,
                        options: [
                            (7, "7 days"),
                            (30, "30 days"),
                            (90, "90 days"),
                            (365, "1 year"),
                        ]
                    )
                    SettingsControlRow(
                        title: "History actions",
                        detail: "Open related windows or clear completed local sessions."
                    ) {
                        HStack(spacing: 8) {
                            Button("Open Activity Center") { runtime.openActivityCenter() }
                                .buttonStyle(NotchPillButtonStyle())
                            Button("Show Setup") { runtime.openOnboarding() }
                                .buttonStyle(NotchPillButtonStyle())
                            Button("Clear History", role: .destructive) {
                                confirmsClearHistory = true
                            }
                            .buttonStyle(NotchPillButtonStyle(destructive: true))
                            .disabled(runtime.activity.recentSessions.isEmpty)
                        }
                    }
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
                            .fill(statusColor(for: integration.status))
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

    @ViewBuilder
    private var updateControl: some View {
        switch runtime.updates.state {
        case .idle:
            Button("Check for Updates") { Task { await runtime.updates.check() } }
                .buttonStyle(NotchPillButtonStyle())
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
                .buttonStyle(NotchPillButtonStyle())
        case let .failed(message):
            Button("Retry") { Task { await runtime.updates.check() } }
                .buttonStyle(NotchPillButtonStyle())
                .help(message)
        }
    }

    private func showsStatus(_ status: ProviderIntegrationStatus) -> Bool {
        switch status {
        case .unavailable: true
        case .notInstalled, .awaitingFirstEvent, .connected: false
        }
    }

    private func statusColor(for status: ProviderIntegrationStatus) -> Color {
        switch status {
        case .connected: .green
        case .awaitingFirstEvent: .orange
        case .notInstalled: .secondary
        case .unavailable: .red
        }
    }
}

// MARK: - Settings chrome

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

/// Section of title + detail rows, matching T3 Code’s flat settings list.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(NotchWindowFont.sectionLabel)
                .foregroundStyle(.white.opacity(0.74))
                .padding(.bottom, 8)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Title + optional detail on the left, control trailing on the right.
private struct SettingsControlRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if let detail {
                    Text(detail)
                        .font(NotchWindowFont.caption)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
                .layoutPriority(1)
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.accentColor)
        }
    }
}

private struct SettingsMenuRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            NotchMenuPicker(
                selection: $selection,
                options: options.map { (value: $0.0, title: $0.1) }
            )
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

private extension View {
    func settingsPanePadding() -> some View {
        padding(.horizontal, NotchWindowMetrics.contentInset)
            .padding(.top, 18)
            .padding(.bottom, 16)
    }
}
