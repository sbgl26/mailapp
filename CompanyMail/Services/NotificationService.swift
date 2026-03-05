import Foundation
import UserNotifications

/// Service de notifications push et locales
final class NotificationService: @unchecked Sendable {
    static let shared = NotificationService()

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            print("Erreur permission notification: \(error)")
            return false
        }
    }

    // MARK: - New Email Notification

    func showNewEmailNotification(from: String, subject: String, snippet: String, accountId: String) async {
        let content = UNMutableNotificationContent()
        content.title = from
        content.subtitle = subject
        content.body = snippet
        content.sound = .default
        content.categoryIdentifier = "NEW_EMAIL"
        content.userInfo = ["accountId": accountId]
        content.threadIdentifier = accountId

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Erreur envoi notification: \(error)")
        }
    }

    // MARK: - Snooze Notification

    func scheduleSnoozeNotification(for email: Email, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Rappel: \(email.from.displayName)"
        content.subtitle = email.subject
        content.body = email.snippet
        content.sound = .default
        content.categoryIdentifier = "SNOOZED_EMAIL"
        content.userInfo = [
            "emailId": email.id,
            "accountId": email.accountId
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: "snooze-\(email.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Erreur programmation rappel: \(error)")
        }
    }

    // MARK: - Badge

    func updateBadge(count: Int) async {
        #if os(iOS)
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(count)
        }
        #endif
    }

    // MARK: - Setup Categories

    func setupCategories() {
        let replyAction = UNNotificationAction(
            identifier: "REPLY",
            title: "Répondre",
            options: .foreground
        )
        let archiveAction = UNNotificationAction(
            identifier: "ARCHIVE",
            title: "Archiver",
            options: .destructive
        )
        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ",
            title: "Marquer comme lu",
            options: []
        )

        let newEmailCategory = UNNotificationCategory(
            identifier: "NEW_EMAIL",
            actions: [replyAction, archiveAction, markReadAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let snoozedCategory = UNNotificationCategory(
            identifier: "SNOOZED_EMAIL",
            actions: [replyAction, archiveAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        UNUserNotificationCenter.current().setNotificationCategories([newEmailCategory, snoozedCategory])
    }
}
