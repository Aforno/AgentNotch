import AgentsNotchCore
import Foundation
import Observation
import os
import UserNotifications

@Observable
@MainActor
final class AgentNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var onOpenSession: ((String) -> Void)?

    private let center: UNUserNotificationCenter?
    nonisolated private static let logger = Logger(
        subsystem: "com.afonsoferreira.AgentNotch",
        category: "notifications"
    )
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
        // The async `requestAuthorization` is nonisolated. Hop through the
        // completion-based API so a MainActor-isolated center is not sent
        // across isolation on Swift 6.1 / macOS 15.
        let granted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        refreshAuthorizationStatus()
        return granted
    }

    func deliverAttention(for session: AgentSession, waitingCount: Int) {
        deliver(
            id: "agent-attention-\(session.id)",
            title: waitingCount > 1
                ? "\(waitingCount) agents need you"
                : "\(session.provider.displayName) needs you",
            session: session,
            soundEnabled: UserDefaults.standard.bool(
                forKey: AppPreferences.Key.attentionNotificationSoundEnabled
            )
        )
    }

    func deliverFailure(for session: AgentSession) {
        guard UserDefaults.standard.bool(forKey: AppPreferences.Key.failureNotificationsEnabled) else {
            return
        }
        deliver(
            id: "agent-failure-\(session.id)",
            title: "\(session.provider.displayName) failed",
            session: session,
            soundEnabled: UserDefaults.standard.bool(
                forKey: AppPreferences.Key.attentionNotificationSoundEnabled
            )
        )
    }

    func removeNotification(for sessionID: String) {
        let identifiers = [
            "agent-attention-\(sessionID)",
            "agent-failure-\(sessionID)",
        ]
        center?.removeDeliveredNotifications(withIdentifiers: identifiers)
        center?.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func refreshAuthorizationStatus() {
        guard let center else { return }
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self?.authorizationStatus = status
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
        }
        completionHandler()
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

    private func deliver(id: String, title: String, session: AgentSession, soundEnabled: Bool) {
        guard UserDefaults.standard.bool(forKey: AppPreferences.Key.attentionNotificationsEnabled),
              let center else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        // Privacy mode must gate every user-derived field, including the
        // project name in the subtitle.
        let isPrivate = UserDefaults.standard.bool(forKey: AppPreferences.Key.privacyModeEnabled)
        content.subtitle = isPrivate
            ? session.provider.displayName
            : projectName(for: session)
        content.body = isPrivate ? session.state.displayName : session.currentActivity
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["sessionID": session.id]
        if soundEnabled {
            content.sound = .default
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error {
                Self.logger.error("Failed to schedule notification \(id): \(error.localizedDescription)")
            }
        }
    }

    private func projectName(for session: AgentSession) -> String {
        session.projectName ?? session.task
    }
}
