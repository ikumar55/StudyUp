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
        /// Next-interval labels for Wrong, Right, Easy, e.g. ["10m", "3d", "8d"].
        static let intervals = "intervals"
    }

    @MainActor
    static func userInfo(for card: Card, path: String, intervals: [String]) -> [String: Any] {
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
        ]
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

/// Hands a tapped reminder's card from the notification delegate to the UI.
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var pendingCardID: PersistentIdentifier?
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

    /// Show reminders even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = ReminderPayload.target(from: response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        Task { @MainActor in
            if let target {
                if action == UNNotificationDefaultActionIdentifier {
                    NotificationRouter.shared.pendingCardID = target.cardID
                } else if let rating = GradeAction.rating(forIdentifier: action) {
                    await NotificationGrader.grade(cardID: target.cardID, expectedReps: target.reps, rating: rating)
                }
            }
            completionHandler()
        }
    }
}
