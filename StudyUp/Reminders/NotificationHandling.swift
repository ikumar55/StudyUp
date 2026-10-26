import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

/// What a reminder carries in its userInfo. The notification content extension reads the same keys
/// (StudyUpNotificationContent/NotificationViewController.swift), so keep them in sync.
nonisolated enum ReminderPayload {
    static let categoryIdentifier = "STUDY_CARD"

    enum Key {
        static let cardID = "cardID"
        static let reps = "reps"
        static let front = "front"
        static let back = "back"
        static let path = "path"
        /// When each answer brings the card back, for Wrong, Right, Easy, e.g. ["again today", "in 3 days", "in 8 days"].
        static let intervals = "intervals"
        /// Sync ids of every card the reminder covers, so tapping it reviews exactly the planned cards.
        static let cardIDs = "cardIDs"
    }

    @MainActor
    static func userInfo(for card: Card, path: String, intervals: [String], cardIDs: [UUID]) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(card.persistentModelID),
              let cardID = String(data: data, encoding: .utf8)
        else { return [:] }
        return [
            Key.cardID: cardID,
            Key.reps: card.reps,
            Key.front: card.front,
            Key.back: card.back,
            Key.path: path,
            Key.intervals: intervals,
            Key.cardIDs: cardIDs.map(\.uuidString),
        ]
    }

    static func cardIDs(from userInfo: [AnyHashable: Any]) -> [UUID] {
        (userInfo[Key.cardIDs] as? [String] ?? []).compactMap(UUID.init(uuidString:))
    }

    /// The card a reminder is about, and how many times it had been reviewed when the reminder was made.
    static func target(from userInfo: [AnyHashable: Any]) -> (cardID: PersistentIdentifier, reps: Int)? {
        guard let string = userInfo[Key.cardID] as? String,
              let cardID = try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(string.utf8))
        else { return nil }
        return (cardID, userInfo[Key.reps] as? Int ?? 0)
    }
}

/// The Wrong / Right / Easy buttons shown on an expanded reminder.
nonisolated enum GradeAction {
    static let ratings: [(rating: Rating, title: String)] = [(.again, "Wrong"), (.good, "Right"), (.easy, "Easy")]

    static func identifier(for rating: Rating) -> String {
        "grade.\(rating.rawValue)"
    }

    static func rating(forIdentifier identifier: String) -> Rating? {
        ratings.first { self.identifier(for: $0.rating) == identifier }?.rating
    }

    static var category: UNNotificationCategory {
        let actions = ratings.map { rating, title in
            UNNotificationAction(
                identifier: identifier(for: rating), title: title,
                options: rating == .again ? [.destructive] : []
            )
        }
        return UNNotificationCategory(identifier: ReminderPayload.categoryIdentifier, actions: actions, intentIdentifiers: [])
    }
}

/// A tapped reminder, handed from the notification delegate to the UI.
nonisolated struct ReminderTap: Equatable, Sendable {
    /// The card the notification showed.
    var cardID: PersistentIdentifier
    /// Every card the reminder covers, in order (sync ids).
    var cardIDs: [UUID]
}

@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var pendingReminder: ReminderTap?
    /// Whether a study session is on screen; reminders then arrive quietly instead of interrupting it.
    var isStudying = false
}

/// Records a grade chosen from a reminder's action buttons, usually with the app in the background.
enum NotificationGrader {
    static func grade(cardID: PersistentIdentifier, expectedReps: Int, rating: Rating, now: Date = .now) async {
        let context = Persistence.container.mainContext
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.persistentModelID == cardID })
        // Ignore stale reminders for cards reviewed since the reminder was made.
        guard let card = try? context.fetch(descriptor).first, card.reps == expectedReps else { return }
        card.record(rating, fsrs: StudySettings.fsrs(desiredRetention: StudySettings.desiredRetention()), context: context, now: now)
        try? context.save()
        await ReminderScheduler.shared.reschedule(context: context).value
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes so a tap that cold-launches the app is delivered.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([GradeAction.category])
        return true
    }

    // These use completion handlers rather than the async variants: UIKit aborts if the async
    // variant's completion runs off the main thread, which it does after a background action.

    /// Show reminders even while the app is open, except during a study session, where a banner
    /// would interrupt (and tapping it would replace the session). They still go to Notification Center.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler(NotificationRouter.shared.isStudying ? [.list] : [.banner, .list, .sound])
            // The app is open, so nothing else would update it: move this one to "Earlier today",
            // show the next time on Home, and fold any cards it covered back into the plan.
            ReminderScheduler.shared.reschedule(context: Persistence.container.mainContext)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let target = ReminderPayload.target(from: userInfo)
        let cardIDs = ReminderPayload.cardIDs(from: userInfo)
        let action = response.actionIdentifier
        Task { @MainActor in
            if let target {
                if action == UNNotificationDefaultActionIdentifier {
                    NotificationRouter.shared.pendingReminder = ReminderTap(cardID: target.cardID, cardIDs: cardIDs)
                } else if let rating = GradeAction.rating(forIdentifier: action) {
                    await NotificationGrader.grade(cardID: target.cardID, expectedReps: target.reps, rating: rating)
                }
            }
            completionHandler()
        }
    }
}
