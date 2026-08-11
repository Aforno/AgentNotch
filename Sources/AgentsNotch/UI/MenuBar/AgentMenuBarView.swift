import AgentsNotchCore
import AppKit
import SwiftUI

struct AgentMenuBarView: View {
    let runtime: AppRuntime
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = false

    var body: some View {
        let snapshot = runtime.activity.notchSnapshot
        if snapshot.attentionCount > 0 {
            Section("Needs Attention (\(snapshot.attentionCount))") {
                ForEach(snapshot.attentionSessions.prefix(3)) { session in
                    Button(shortTitle(for: session)) {
                        runtime.open(session)
                    }
                }
            }
        }

        let active = snapshot.activeSessions.filter { $0.state != .waitingForUser }
        if !active.isEmpty {
            Section("Active (\(active.count))") {
                ForEach(active.prefix(3)) { session in
                    Button(shortTitle(for: session)) {
                        runtime.open(session)
                    }
                }
            }
        }

        Section {
            Button("Open Activity Center") { runtime.openActivityCenter() }
                .keyboardShortcut("1", modifiers: [.command])
            Button("Show Setup") { runtime.openOnboarding() }
            Button("Settings…") { runtime.openSettings() }
                .keyboardShortcut(",", modifiers: [.command])
        }

        Divider()

        Button("Quit Agents Notch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func shortTitle(for session: AgentSession) -> String {
        let project = session.workingDirectory
            .map { URL(fileURLWithPath: $0).lastPathComponent }
            ?? session.provider.displayName
        let activity = privacyModeEnabled ? session.state.displayName : session.currentActivity
        let title = "\(project): \(activity)"
        guard title.count > 30 else { return title }
        return String(title.prefix(27)) + "…"
    }
}
