import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

/// Encodes which card a reminder is about into the notification's userInfo.
nonisolated enum ReminderPayload {
    static let cardIDKey = "cardID"

    static func userInfo(cardID: PersistentIdentifier) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(cardID),
              let string = String(data: data, encoding: .utf8)
        else { return [:] }
        return [cardIDKey: string]
    }

    static func cardID(from userInfo: [AnyHashable: Any]) -> PersistentIdentifier? {
        guard let string = userInfo[cardIDKey] as? String else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(string.utf8))
    }
}

/// Hands a tapped reminder's card from the notification delegate to the UI.
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    var pendingCardID: PersistentIdentifier?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes so a tap that cold-launches the app is delivered.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show reminders even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let cardID = ReminderPayload.cardID(from: response.notification.request.content.userInfo)
        else { return }
        await MainActor.run {
            NotificationRouter.shared.pendingCardID = cardID
        }
    }
}
