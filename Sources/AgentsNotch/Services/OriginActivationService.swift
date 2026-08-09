import AgentsNotchCore
import AppKit

@MainActor
struct OriginActivationService {
    @discardableResult
    func open(_ session: AgentSession) -> Bool {
        if let applicationURL = session.applicationURL,
           NSWorkspace.shared.open(applicationURL) {
            return true
        }

        if let processIdentifier = session.origin?.processIdentifier,
           let application = NSRunningApplication(processIdentifier: processIdentifier),
           application.activationPolicy != .prohibited,
           application.activate() {
            return true
        }

        if let bundleIdentifier = session.origin?.bundleIdentifier,
           let application = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first,
           application.activate() {
            return true
        }

        if let directory = session.workingDirectory {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory)])
            return true
        }
        return false
    }

    func openFile(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
