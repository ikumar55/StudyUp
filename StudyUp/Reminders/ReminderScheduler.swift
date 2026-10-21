import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

/// One planned reminder: when it goes off and the cards it covers (by sync id).
nonisolated struct PlannedReminder: Codable, Equatable, Identifiable, Sendable {
    var fireDate: Date
    var cardIDs: [UUID]
    var id: Date { fireDate }
}

/// Keeps the pending study-reminder notifications in sync with what's due.
/// iOS can't wake the app on demand, so reminders are planned several days ahead
/// (assuming nothing is reviewed in between) and replanned whenever the app runs.
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var nextReminderDate: Date?
    /// Today's reminders still to come, as currently planned.
    private(set) var upcomingToday: [PlannedReminder] = []
    /// Today's reminders that have already gone out.
    private(set) var sentToday: [PlannedReminder] = []

    private let defaults = UserDefaults.standard
    private enum Key {
        static let upcomingToday = "reminders.upcomingToday"
        static let sentToday = "reminders.sentToday"
    }

    init() {
        upcomingToday = load(Key.upcomingToday)
        sentToday = load(Key.sentToday)
        recordSentReminders(now: .now)
    }

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
            recordSentReminders(now: now)
            guard canSchedule else {
                nextReminderDate = nil
                setUpcomingToday([])
                return
            }
            for (request, _) in planned {
                try? await center.add(request)
            }
            nextReminderDate = planned.map(\.reminder.fireDate).min()
            setUpcomingToday(planned.map(\.reminder).filter { Calendar.current.isDate($0.fireDate, inSameDayAs: now) })
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
            content: content(for: card, cardIDs: card.syncID.map { [$0] } ?? [], at: fireDate, fsrs: currentFSRS()),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try? await center.add(request)
        return true
    }

    // MARK: - Planning

    private func plan(context: ModelContext, settings: ReminderSettings, now: Date) -> [(request: UNNotificationRequest, reminder: PlannedReminder)] {
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

        var planned: [(request: UNNotificationRequest, reminder: PlannedReminder)] = []
        for (dayStart, newLimit) in days {
            let ordered = StudyQueue.reminderCandidates(from: cards, dayStart: dayStart, newLimit: newLimit, calendar: calendar)
            let candidates = ordered.indices.map { ReminderPlanner.Candidate(id: $0, availableAt: ordered[$0].availableAt) }
            let reminders = ReminderPlanner.planDay(candidates: candidates, dayStart: dayStart, now: now, settings: settings)
            for reminder in reminders {
                let cards = reminder.cardIDs.map { ordered[$0].card }
                let cardIDs = cards.compactMap(\.syncID)
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
                // Unique per fire time, so a new plan never replaces a reminder already showing.
                let request = UNNotificationRequest(
                    identifier: "\(Self.plannedIdentifierPrefix)\(Int(reminder.fireDate.timeIntervalSince1970))",
                    content: content(for: cards[0], cardIDs: cardIDs, at: reminder.fireDate, fsrs: fsrs),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                planned.append((request, PlannedReminder(fireDate: reminder.fireDate, cardIDs: cardIDs)))
            }
        }
        return planned
    }

    /// - Parameter cardIDs: Every card the reminder covers; the first is the one it shows.
    private func content(for card: Card, cardIDs: [UUID], at fireDate: Date, fsrs: FSRS) -> UNNotificationContent {
        let extraCards = max(cardIDs.count - 1, 0)
        let content = UNMutableNotificationContent()
        content.title = card.folder?.path ?? "StudyUp"
        content.body = PlainText.from(markdown: ImageStore.replacingReferences(in: card.front))
        if extraCards > 0 {
            content.subtitle = "+ \(extraCards) more \(extraCards == 1 ? "card" : "cards")"
        }
        content.sound = .default
        content.threadIdentifier = "study"
        content.categoryIdentifier = ReminderPayload.categoryIdentifier
        // Intervals as of the fire time; any change to the card triggers a replan anyway.
        let previews = fsrs.preview(card.schedule, now: fireDate)
        let intervals = GradeAction.ratings.map { rating, _ in
            previews[rating].map { DueText.next($0.due, from: fireDate, rating: rating) } ?? ""
        }
        content.userInfo = ReminderPayload.userInfo(for: card, path: content.title, intervals: intervals, cardIDs: cardIDs)
        content.attachments = attachments(for: card)
        return content
    }

    /// The card's first few images, for the banner and the long-press view. Question images show as
    /// the banner's thumbnail; answer images stay hidden until the reminder is expanded.
    private func attachments(for card: Card) -> [UNNotificationAttachment] {
        let question = ImageStore.references(in: card.front).map { (id: $0, isAnswer: false) }
        let answer = ImageStore.references(in: card.back).map { (id: $0, isAnswer: true) }
        return (question + answer).prefix(3).compactMap { image in
            // iOS moves attachment files into its own store, so each reminder gets its own copy.
            guard let source = notificationImage(for: image.id) else { return nil }
            let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpg")
            guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil else { return nil }
            return try? UNNotificationAttachment(
                identifier: "\(image.isAnswer ? "answer" : "question")-\(image.id.uuidString)",
                url: copy,
                options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: image.isAnswer]
            )
        }
    }

    /// A JPEG version of an image sized for notifications, made once and cached, since reminders
    /// are replanned often and notifications don't accept WebP.
    private func notificationImage(for id: UUID) -> URL? {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "NotificationImages", directoryHint: .isDirectory)
        let cached = cache.appending(path: "\(id.uuidString.lowercased()).jpg")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }
        guard let url = ImageStore.shared.url(for: id), let image = UIImage(contentsOfFile: url.path) else { return nil }
        let scale = min(1, 1200 / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return (try? data.write(to: cached, options: .atomic)) == nil ? nil : cached
    }

    // MARK: - Today's reminders

    /// Moves reminders whose time has passed from "upcoming" to "sent", and forgets earlier days.
    private func recordSentReminders(now: Date) {
        let calendar = Calendar.current
        let fired = upcomingToday.filter { $0.fireDate <= now }
        let sent = (sentToday + fired).filter { calendar.isDate($0.fireDate, inSameDayAs: now) }
        sentToday = Array(Dictionary(sent.map { ($0.fireDate, $0) }, uniquingKeysWith: { first, _ in first }).values)
            .sorted { $0.fireDate < $1.fireDate }
        save(sentToday, Key.sentToday)
        setUpcomingToday(upcomingToday.filter { $0.fireDate > now && calendar.isDate($0.fireDate, inSameDayAs: now) })
    }

    private func setUpcomingToday(_ reminders: [PlannedReminder]) {
        upcomingToday = reminders.sorted { $0.fireDate < $1.fireDate }
        save(upcomingToday, Key.upcomingToday)
    }

    private func load(_ key: String) -> [PlannedReminder] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PlannedReminder].self, from: $0) } ?? []
    }

    private func save(_ reminders: [PlannedReminder], _ key: String) {
        defaults.set(try? JSONEncoder().encode(reminders), forKey: key)
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
