import Foundation
import Observation
import SwiftData
import UserNotifications

/// Keeps the pending study-reminder notifications in sync with what's due.
/// iOS can't wake the app on demand, so reminders are planned several days ahead
/// (assuming nothing is reviewed in between) and replanned whenever the app runs.
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var nextReminderDate: Date?

    private let center = UNUserNotificationCenter.current()
    /// iOS keeps at most 64 pending notifications per app; leave room for a test reminder.
    private static let pendingBudget = 60
    private static let maxDaysAhead = 7
    private static let plannedIdentifierPrefix = "reminder-"
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
            // Only replace planned reminders; a test reminder must survive a replan.
            let plannedIDs = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(Self.plannedIdentifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: plannedIDs)
            await removeStaleDeliveredReminders(context: context)
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
        let fireDate = Date.now.addingTimeInterval(5)
        let request = UNNotificationRequest(
            identifier: "test-reminder-\(Int(fireDate.timeIntervalSince1970))",
            content: content(for: card, extraCards: 0, at: fireDate, fsrs: currentFSRS()),
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
        let newCardsPerDay = StudySettings.newCardsPerDay()
        let fsrs = currentFSRS()
        // As many days as fit in the pending-notification budget: 7 days at 8 a day, 3 at 20.
        let dayCount = min(Self.maxDaysAhead, max(2, Self.pendingBudget / max(settings.maxPerDay, 1)))
        let days = (0..<dayCount).map { offset in
            (
                calendar.date(byAdding: .day, value: offset, to: today)!,
                offset == 0 ? StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context, now: now) : newCardsPerDay
            )
        }

        var planned: [(request: UNNotificationRequest, fireDate: Date)] = []
        for (dayStart, newLimit) in days {
            let ordered = StudyQueue.reminderCandidates(from: cards, dayStart: dayStart, newLimit: newLimit, calendar: calendar)
            let candidates = ordered.indices.map { ReminderPlanner.Candidate(id: $0, availableAt: ordered[$0].availableAt) }
            let reminders = ReminderPlanner.planDay(candidates: candidates, dayStart: dayStart, now: now, settings: settings)
            for reminder in reminders {
                let card = ordered[reminder.cardIDs[0]].card
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
                // Unique per fire time, so a new plan never replaces a reminder already showing.
                let request = UNNotificationRequest(
                    identifier: "\(Self.plannedIdentifierPrefix)\(Int(reminder.fireDate.timeIntervalSince1970))",
                    content: content(for: card, extraCards: reminder.cardIDs.count - 1, at: reminder.fireDate, fsrs: fsrs),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                planned.append((request, reminder.fireDate))
            }
        }
        return planned
    }

    private func content(for card: Card, extraCards: Int, at fireDate: Date, fsrs: FSRS) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = card.folder?.path ?? "StudyUp"
        content.body = PlainText.from(markdown: card.front)
        if extraCards > 0 {
            content.subtitle = "+ \(extraCards) more \(extraCards == 1 ? "card" : "cards")"
        }
        content.sound = .default
        content.threadIdentifier = "study"
        content.categoryIdentifier = ReminderPayload.categoryIdentifier
        // Intervals as of the fire time; any change to the card triggers a replan anyway.
        let previews = fsrs.preview(card.schedule, now: fireDate)
        let intervals = GradeAction.ratings.map { rating, _ in
            previews[rating].map { IntervalText.short($0.due.timeIntervalSince(fireDate)) } ?? ""
        }
        content.userInfo = ReminderPayload.userInfo(for: card, path: content.title, intervals: intervals)
        return content
    }

    private func currentFSRS() -> FSRS {
        StudySettings.fsrs(desiredRetention: StudySettings.desiredRetention())
    }

    /// Clears reminders still in Notification Center whose card was deleted or reviewed since.
    private func removeStaleDeliveredReminders(context: ModelContext) async {
        let delivered = await center.deliveredNotifications()
        let stale = delivered.compactMap { notification -> String? in
            guard let target = ReminderPayload.target(from: notification.request.content.userInfo) else { return nil }
            let cardID = target.cardID
            let card = try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.persistentModelID == cardID })).first
            return card?.reps == target.reps ? nil : notification.request.identifier
        }
        center.removeDeliveredNotifications(withIdentifiers: stale)
    }
}
