import AppKit
import SwiftUI

struct GeneralSettingsPane: View {
    let runtime: AppRuntime
    let launchAtLogin: Binding<Bool>
    let animationsEnabled: Binding<Bool>
    let notchEnabled: Binding<Bool>
    let showVirtualNotch: Binding<Bool>
    let automaticallyCheckForUpdates: Binding<Bool>
    let updateChannel: Binding<String>
    let displayPreference: Binding<String>
    let globalActivityShortcut: Binding<String>
    let launchError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsHeading(
                    title: "General",
                    detail: "Control how Agent Notch starts and presents activity."
                )
                RuntimeHealthBanner(runtime: runtime)
                notchSection
                systemSection
                updatesSection
                HStack {
                    Spacer()
                    Button("Quit Agent Notch") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(NotchPillButtonStyle())
                }
            }
            .settingsPanePadding()
        }
        .background(NotchWindowPalette.background)
    }

    private var notchSection: some View {
        SettingsSection(title: "Notch") {
            SettingsToggleRow(title: "Show notch surface", isOn: notchEnabled)
            SettingsMenuRow(
                title: "Show the notch on",
                selection: displayPreference,
                options: DisplayPreference.allCases.map { ($0.rawValue, $0.title) }
            )
            SettingsToggleRow(
                title: "Virtual notch",
                detail: "For displays without a camera housing.",
                isOn: showVirtualNotch
            )
            SettingsToggleRow(title: "Animate transitions", isOn: animationsEnabled)
        }
    }

    private var systemSection: some View {
        SettingsSection(title: "System") {
            SettingsToggleRow(title: "Launch at login", isOn: launchAtLogin)
            SettingsMenuRow(
                title: "Global activity shortcut",
                detail: "Opens Activity Center from any app.",
                selection: globalActivityShortcut,
                options: GlobalActivityShortcut.allCases.map { ($0.rawValue, $0.title) }
            )
            if let launchError {
                SettingsMessage(
                    text: launchError,
                    symbol: "exclamationmark.triangle.fill",
                    color: NotchWindowPalette.failure
                )
            }
        }
    }

    private var updatesSection: some View {
        SettingsSection(title: "Updates") {
            SettingsToggleRow(
                title: "Check automatically",
                detail: "Downloads and installs only when you ask.",
                isOn: automaticallyCheckForUpdates
            )
            SettingsMenuRow(
                title: "Update channel",
                detail: "Nightly builds track main and may be unstable.",
                selection: updateChannel,
                options: UpdateChannel.allCases.map { ($0.rawValue, $0.title) }
            )
            SettingsControlRow(title: "Version \(runtime.updates.currentVersion)") {
                SettingsUpdateControl(updates: runtime.updates)
            }
        }
    }
}
