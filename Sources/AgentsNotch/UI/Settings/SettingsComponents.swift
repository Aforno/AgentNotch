import AppKit
import SwiftUI

struct AttentionSettingsSection: View {
    let notificationsEnabled: Binding<Bool>
    let soundEnabled: Binding<Bool>
    let failureNotificationsEnabled: Binding<Bool>
    let answerFromNotchEnabled: Binding<Bool>

    var body: some View {
        SettingsSection(title: "Attention") {
            SettingsToggleRow(
                title: "Attention notifications",
                detail: "Post a macOS notification when an agent needs input.",
                isOn: notificationsEnabled
            )
            SettingsToggleRow(
                title: "Notification sound",
                isOn: soundEnabled
            )
            .disabled(!notificationsEnabled.wrappedValue)
            SettingsToggleRow(
                title: "Failure notifications",
                detail: "Routine activity never notifies.",
                isOn: failureNotificationsEnabled
            )
            .disabled(!notificationsEnabled.wrappedValue)
            SettingsToggleRow(
                title: "Answer from the notch",
                detail: "Show Deny and Allow on Codex and Claude permission prompts. Other providers stay observers.",
                isOn: answerFromNotchEnabled
            )
        }
    }
}

struct PrivacySettingsSection: View {
    let privacyModeEnabled: Binding<Bool>

    var body: some View {
        SettingsSection(title: "Privacy") {
            SettingsToggleRow(
                title: "Hide activity details",
                detail: "Show only provider, project, and state in the notch and notifications.",
                isOn: privacyModeEnabled
            )
        }
    }
}

struct HistorySettingsSection: View {
    let retentionDays: Binding<Int>
    let hasCompletedSessions: Bool
    let openActivityCenter: () -> Void
    let requestClearHistory: () -> Void

    var body: some View {
        SettingsSection(title: "Local History") {
            SettingsMenuRow(
                title: "Keep finished sessions",
                selection: retentionDays,
                options: [
                    (3, "3 days"),
                    (7, "7 days"),
                ]
            )
            SettingsControlRow(title: "Browse history") {
                Button("Open Activity Center", action: openActivityCenter)
                    .buttonStyle(NotchPillButtonStyle())
            }
            SettingsControlRow(title: "Clear finished sessions", detail: "Active and waiting sessions are kept.") {
                Button("Clear History", role: .destructive, action: requestClearHistory)
                    .buttonStyle(NotchPillButtonStyle(destructive: true))
                    .disabled(!hasCompletedSessions)
            }
        }
    }
}

struct SettingsUpdateControl: View {
    let updates: UpdateService

    @ViewBuilder
    var body: some View {
        switch updates.state {
        case .idle:
            Button("Check for Updates") { updates.check() }
                .buttonStyle(NotchPillButtonStyle())
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.success)
        case let .available(version):
            Button("Download \(version)") { updates.download() }
                .buttonStyle(NotchPillButtonStyle())
                .help(updates.lastError ?? "Download this update, then restart to install it.")
        case let .downloading(_, percent):
            HStack(spacing: 8) {
                ProgressView(value: percent)
                    .frame(width: 72)
                    .controlSize(.small)
                Text("\(Int((percent * 100).rounded()))%")
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
                    .monospacedDigit()
            }
        case let .downloaded(version):
            Button("Restart to Update") { updates.install() }
                .buttonStyle(NotchPillButtonStyle())
                .help(updates.lastError ?? "Install \(version) and relaunch Agent Notch.")
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing")
                    .font(NotchWindowFont.caption)
                    .foregroundStyle(NotchWindowPalette.secondaryText)
            }
        case let .failed(message):
            Button("Retry") { updates.check() }
                .buttonStyle(NotchPillButtonStyle())
                .help(message)
                .accessibilityHint(message)
        case let .unavailable(message):
            Text("Packaged builds only")
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
                .help(message)
        }
    }
}

struct SettingsHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(NotchWindowFont.display)
                .foregroundStyle(NotchWindowPalette.primaryText)
            Text(detail)
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(NotchWindowFont.sectionLabel)
                .foregroundStyle(NotchWindowPalette.secondaryText)
                .padding(.bottom, 8)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let control: Control

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NotchWindowFont.label)
                    .foregroundStyle(NotchWindowPalette.primaryText)
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
        // One dim for the whole row, sized so disabled text lands on the next
        // rung of the ladder (title reads secondary, detail reads tertiary)
        // rather than dropping out of legibility entirely.
        .opacity(isEnabled ? 1 : 0.7)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(NotchWindowPalette.active)
        }
    }
}

struct SettingsMenuRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        SettingsControlRow(title: title, detail: detail) {
            NotchMenuPicker(
                selection: $selection,
                options: options.map { (value: $0.0, title: $0.1) },
                accessibilityLabel: title
            )
        }
    }
}

struct SettingsMessage: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(NotchWindowFont.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Runtime health for Setup and Settings. Renders nothing while healthy.
struct RuntimeHealthBanner: View {
    let runtime: AppRuntime

    var body: some View {
        if runtime.socketError != nil
            || runtime.persistenceError != nil
            || runtime.persistenceRecoveryNotice != nil
            || runtime.activity.protocolMismatchDetected
        {
            RuntimeHealthMessages(
                socketError: runtime.socketError,
                persistenceError: runtime.persistenceError,
                persistenceRecoveryNotice: runtime.persistenceRecoveryNotice,
                protocolMismatchDetected: runtime.activity.protocolMismatchDetected
            )
        }
    }
}

struct RuntimeHealthMessages: View {
    let socketError: String?
    let persistenceError: String?
    let persistenceRecoveryNotice: String?
    var protocolMismatchDetected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if protocolMismatchDetected {
                SettingsMessage(
                    text: "Some agent events were ignored because they use an unsupported protocol version. Reinstall the provider integrations below (or update the app) so hooks and app speak the same protocol.",
                    symbol: "arrow.triangle.branch",
                    color: NotchWindowPalette.attention
                )
            }
            if let socketError {
                SettingsMessage(
                    text: "Local event relay unavailable: \(socketError)",
                    symbol: "network.slash",
                    color: NotchWindowPalette.failure
                )
            }
            if let persistenceError {
                SettingsMessage(
                    text: persistenceError,
                    symbol: "externaldrive.badge.exclamationmark",
                    color: NotchWindowPalette.failure
                )
            }
            if let persistenceRecoveryNotice {
                SettingsMessage(
                    text: persistenceRecoveryNotice,
                    symbol: "externaldrive.badge.checkmark",
                    color: NotchWindowPalette.attention
                )
            }
        }
    }
}

extension View {
    func settingsPanePadding() -> some View {
        padding(.horizontal, NotchWindowMetrics.contentInset)
            .padding(.top, 18)
            .padding(.bottom, 16)
    }
}
