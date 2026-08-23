import AppKit
import SwiftUI

struct ApplicationSettingsSection: View {
    let launchAtLogin: Binding<Bool>
    let animationsEnabled: Binding<Bool>
    let notchEnabled: Binding<Bool>
    let showVirtualNotch: Binding<Bool>
    let automaticallyCheckForUpdates: Binding<Bool>
    let displayPreference: Binding<String>
    let globalActivityShortcut: Binding<String>
    let updates: UpdateService

    var body: some View {
        SettingsSection(title: "Application") {
            SettingsToggleRow(
                title: "Launch at login",
                detail: "Start Agent Notch automatically when you sign in to this Mac.",
                isOn: launchAtLogin
            )
            SettingsToggleRow(
                title: "Animate notch transitions",
                detail: "Smooth open, close, and content changes on the notch surface.",
                isOn: animationsEnabled
            )
            SettingsToggleRow(
                title: "Show notch surface",
                detail: "Display live agent activity on the hardware or virtual notch.",
                isOn: notchEnabled
            )
            SettingsToggleRow(
                title: "Virtual notch",
                detail: "Show a virtual notch on displays without hardware cutouts.",
                isOn: showVirtualNotch
            )
            SettingsToggleRow(
                title: "App update checks",
                detail: "Automatically check GitHub for newer Agent Notch releases.",
                isOn: automaticallyCheckForUpdates
            )
            SettingsMenuRow(
                title: "Show the notch on",
                detail: "Choose which display hosts the notch surface.",
                selection: displayPreference,
                options: DisplayPreference.allCases.map { ($0.rawValue, $0.title) }
            )
            SettingsMenuRow(
                title: "Global activity shortcut",
                detail: "Open Activity Center from any app without Accessibility permission.",
                selection: globalActivityShortcut,
                options: GlobalActivityShortcut.allCases.map { ($0.rawValue, $0.title) }
            )
            SettingsControlRow(title: "Version", detail: "Current app version and update status.") {
                HStack(spacing: 8) {
                    Text(updates.currentVersion)
                        .font(NotchWindowFont.control)
                        .foregroundStyle(NotchWindowPalette.secondaryText)
                    SettingsUpdateControl(updates: updates)
                }
            }
            SettingsControlRow(
                title: "Quit",
                detail: "Stop the notch and stop listening for local agent events."
            ) {
                Button("Quit Agent Notch") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(NotchPillButtonStyle())
            }
        }
    }
}

struct AttentionSettingsSection: View {
    let notificationsEnabled: Binding<Bool>
    let soundEnabled: Binding<Bool>
    let failureNotificationsEnabled: Binding<Bool>
    let answerFromNotchEnabled: Binding<Bool>

    var body: some View {
        SettingsSection(title: "Attention") {
            SettingsToggleRow(
                title: "Attention notifications",
                detail: "Show macOS notifications when an agent needs input.",
                isOn: notificationsEnabled
            )
            SettingsToggleRow(
                title: "Notification sound",
                detail: "Play the system notification sound with attention alerts.",
                isOn: soundEnabled
            )
            .disabled(!notificationsEnabled.wrappedValue)
            .opacity(notificationsEnabled.wrappedValue ? 1 : 0.45)
            SettingsToggleRow(
                title: "Failure notifications",
                detail: "Also notify when an agent fails. Routine activity stays collapsed.",
                isOn: failureNotificationsEnabled
            )
            .disabled(!notificationsEnabled.wrappedValue)
            .opacity(notificationsEnabled.wrappedValue ? 1 : 0.45)
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
    let openOnboarding: () -> Void
    let requestClearHistory: () -> Void

    var body: some View {
        SettingsSection(title: "Local History") {
            SettingsMenuRow(
                title: "Keep completed sessions",
                detail: "How long finished sessions remain in Activity Center.",
                selection: retentionDays,
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
                    Button("Open Activity Center", action: openActivityCenter)
                        .buttonStyle(NotchPillButtonStyle())
                    Button("Show Setup", action: openOnboarding)
                        .buttonStyle(NotchPillButtonStyle())
                    Button("Clear History", role: .destructive, action: requestClearHistory)
                        .buttonStyle(NotchPillButtonStyle(destructive: true))
                        .disabled(!hasCompletedSessions)
                }
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
            Button("Check for Updates") { Task { await updates.check() } }
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
        case let .available(version):
            Button("Download \(version)") { updates.openAvailableRelease() }
                .buttonStyle(NotchPillButtonStyle())
        case let .failed(message):
            Button("Retry") { Task { await updates.check() } }
                .buttonStyle(NotchPillButtonStyle())
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
                .foregroundStyle(.white.opacity(0.92))
            Text(detail)
                .font(NotchWindowFont.caption)
                .foregroundStyle(NotchWindowPalette.secondaryText)
        }
    }
}

/// Section of title + detail rows, matching T3 Code's flat settings list.
struct SettingsSection<Content: View>: View {
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
struct SettingsControlRow<Control: View>: View {
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
                .tint(Color.accentColor)
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
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
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
                    color: .orange
                )
            }
            if let socketError {
                SettingsMessage(
                    text: "Local event relay unavailable: \(socketError)",
                    symbol: "network.slash",
                    color: .red
                )
            }
            if let persistenceError {
                SettingsMessage(
                    text: persistenceError,
                    symbol: "externaldrive.badge.exclamationmark",
                    color: .red
                )
            }
            if let persistenceRecoveryNotice {
                SettingsMessage(
                    text: persistenceRecoveryNotice,
                    symbol: "externaldrive.badge.checkmark",
                    color: .orange
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
