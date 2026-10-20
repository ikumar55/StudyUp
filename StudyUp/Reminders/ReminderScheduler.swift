import Foundation
import Observation
import SwiftData
import UserNotifications

/// Keeps the pending study-reminder notifications in sync with what's due.
/// iOS can't wake the app on demand, so today's and tomorrow's reminders are planned ahead
/// and replanned whenever the app runs.
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var nextReminderDate: Date?

    private let center = UNUserNotificationCenter.current()
    private var pendingUpdate: Task<Void, Never>?

    var canSchedule: Bool {
        [.authorized, .provisional, .ephemeral].contains(authorizationStatus)
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorizationStatus()
    }

    /// Replaces all pending reminders with a fresh plan. Updates run one at a time, in order.
    @discardableResult
    func reschedule(context: ModelContext, now: Date = .now) -> Task<Void, Never> {
        try? context.save()
        let settings = ReminderSettings.load()
        let planned = settings.isEnabled ? plan(context: context, settings: settings, now: now) : []
        let previous = pendingUpdate
        let update = Task {
            await previous?.value
            await refreshAuthorizationStatus()
            center.removeAllPendingNotificationRequests()
            guard canSchedule else {
                nextReminderDate = nil
                return
            }
            for (request, _) in planned {
                try? await center.add(request)
            }
            nextReminderDate = planned.map(\.fireDate).min()
        }
        pendingUpdate = update
        return update
    }

    /// Sends a reminder for the next due card (or any card) in 5 seconds. Returns false if there are no cards.
    func sendTestReminder(context: ModelContext) async -> Bool {
        if authorizationStatus == .notDetermined { await requestAuthorization() }
        guard canSchedule else { return false }
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        guard let card = StudyQueue.build(from: cards, newLimit: .max).first ?? cards.first else { return false }
        try? context.save()
        let request = UNNotificationRequest(
            identifier: "test-reminder",
            content: content(for: card, extraCards: 0),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try? await center.add(request)
        return true
    }

    // MARK: - Planning

    private func plan(context: ModelContext, settings: ReminderSettings, now: Date) -> [(request: UNNotificationRequest, fireDate: Date)] {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let newCardsPerDay = StudySettings.newCardsPerDay()
        let days = [
            (today, StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context, now: now)),
            (tomorrow, newCardsPerDay),
        ]

        var planned: [(request: UNNotificationRequest, fireDate: Date)] = []
        for (dayStart, newLimit) in days {
            let ordered = StudyQueue.reminderCandidates(from: cards, dayStart: dayStart, newLimit: newLimit, calendar: calendar)
            let candidates = ordered.indices.map { ReminderPlanner.Candidate(id: $0, availableAt: ordered[$0].availableAt) }
            let reminders = ReminderPlanner.planDay(candidates: candidates, dayStart: dayStart, now: now, settings: settings)
            for (index, reminder) in reminders.enumerated() {
                let card = ordered[reminder.cardIDs[0]].card
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
                let request = UNNotificationRequest(
                    identifier: "reminder-\(Int(dayStart.timeIntervalSince1970))-\(index)",
                    content: content(for: card, extraCards: reminder.cardIDs.count - 1),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                planned.append((request, reminder.fireDate))
            }
        }
        return planned
    }

    private func content(for card: Card, extraCards: Int) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = card.folder?.path ?? "StudyUp"
        content.body = PlainText.from(markdown: card.front)
        if extraCards > 0 {
            content.subtitle = "+ \(extraCards) more \(extraCards == 1 ? "card" : "cards")"
        }
        content.sound = .default
        content.threadIdentifier = "study"
        content.userInfo = ReminderPayload.userInfo(cardID: card.persistentModelID)
        return content
    }
}
