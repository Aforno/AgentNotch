import AgentsNotchCore
import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class AgentNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var onOpenSession: ((String) -> Void)?

    private let center: UNUserNotificationCenter?
    private static let categoryIdentifier = "AGENT_ATTENTION"
    private static let openActionIdentifier = "OPEN_SESSION"

    override init() {
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        center?.delegate = self
        registerCategories()
        refreshAuthorizationStatus()
    }

    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            refreshAuthorizationStatus()
            return true
        }
        guard let center else { return false }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            refreshAuthorizationStatus()
            return granted
        } catch {
            refreshAuthorizationStatus()
            return false
        }
    }

    func deliverAttention(for session: AgentSession, waitingCount: Int) {
        guard UserDefaults.standard.bool(forKey: "attentionNotificationsEnabled") else { return }
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = waitingCount > 1
            ? "\(waitingCount) agents need you"
            : "\(session.provider.displayName) needs you"
        content.subtitle = projectName(for: session)
        content.body = notificationBody(for: session)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["sessionID": session.id]
        if UserDefaults.standard.bool(forKey: "attentionNotificationSoundEnabled") {
            content.sound = .default
        }
        center.add(UNNotificationRequest(
            identifier: "agent-attention-\(session.id)",
            content: content,
            trigger: nil
        ))
    }

    func deliverFailure(for session: AgentSession) {
        guard UserDefaults.standard.bool(forKey: "attentionNotificationsEnabled"),
              UserDefaults.standard.bool(forKey: "failureNotificationsEnabled"),
              let center else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(session.provider.displayName) failed"
        content.subtitle = projectName(for: session)
        content.body = notificationBody(for: session)
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["sessionID": session.id]
        if UserDefaults.standard.bool(forKey: "attentionNotificationSoundEnabled") {
            content.sound = .default
        }
        center.add(UNNotificationRequest(
            identifier: "agent-failure-\(session.id)",
            content: content,
            trigger: nil
        ))
    }

    func removeNotification(for sessionID: String) {
        center?.removeDeliveredNotifications(withIdentifiers: ["agent-attention-\(sessionID)"])
        center?.removePendingNotificationRequests(withIdentifiers: ["agent-attention-\(sessionID)"])
    }

    func refreshAuthorizationStatus() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        Task { @MainActor [weak self] in
            if let sessionID {
                self?.onOpenSession?(sessionID)
            }
            completionHandler()
        }
    }

    private func registerCategories() {
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "Open Session",
            options: [.foreground]
        )
        center?.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [open],
                intentIdentifiers: []
            ),
        ])
    }

    private func projectName(for session: AgentSession) -> String {
        if let directory = session.workingDirectory {
            return URL(fileURLWithPath: directory).lastPathComponent
        }
        return UserDefaults.standard.bool(forKey: "privacyModeEnabled")
            ? session.provider.displayName
            : session.task
    }

    private func notificationBody(for session: AgentSession) -> String {
        UserDefaults.standard.bool(forKey: "privacyModeEnabled")
            ? session.state.displayName
            : session.currentActivity
    }
}
