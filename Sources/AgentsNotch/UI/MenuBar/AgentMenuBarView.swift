import AgentsNotchCore
import AppKit
import SwiftUI

struct AgentMenuBarView: View {
    let runtime: AppRuntime

    var body: some View {
        if runtime.activity.attentionCount > 0 {
            Section("Needs Attention") {
                ForEach(runtime.activity.attentionSessions.prefix(3)) { session in
                    Button(shortTitle(for: session)) {
                        runtime.presentSession(session.id)
                        runtime.openActivityCenter()
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
        let title = "\(project): \(session.currentActivity)"
        guard title.count > 30 else { return title }
        return String(title.prefix(27)) + "…"
    }
}
