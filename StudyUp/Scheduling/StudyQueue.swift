import Foundation
import SwiftData

enum StudyScope {
    /// Every card that comes up: not in a paused folder, and in a focused one if any are focused.
    case all
    /// A folder's cards, paused or not, for studying it on purpose.
    case folder(Folder)
}

/// Decides which cards are ready to study right now.
enum StudyQueue {
    static func cards(in scope: StudyScope, context: ModelContext) -> [Card] {
        switch scope {
        case .all: comingUp(context: context)
        case .folder(let folder): folder.allCards
        }
    }

    /// The cards that come up in notifications, Home's Study now and the counts (see `FolderModes`).
    static func comingUp(context: ModelContext) -> [Card] {
        ((try? context.fetch(FetchDescriptor<Card>())) ?? []).filter(FolderModes.shared.includes)
    }

    /// Learning cards first, then reviews due today, then new cards up to `newLimit`. New cards from
    /// notifications that went unanswered (`missed`, see `missedToday`) come first and always come in,
    /// since they were already today's.
    static func build(
        from cards: [Card], newLimit: Int, missed: Set<ObjectIdentifier> = [], now: Date = .now, calendar: Calendar = .current
    ) -> [Card] {
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var learning: [Card] = []
        var review: [Card] = []
        var new: [Card] = []
        for card in cards {
            switch card.state {
            case .learning, .relearning:
                // Only once due: a card missed a moment ago waits for the next reminder.
                if card.due <= now { learning.append(card) }
            case .review:
                if card.due < startOfTomorrow { review.append(card) }
            case .new:
                new.append(card)
            }
        }
        learning.sort { $0.due < $1.due }
        review.sort { $0.due < $1.due }
        new.sort { $0.createdAt < $1.createdAt }
        let missedNew = new.filter { missed.contains(ObjectIdentifier($0)) }
        let otherNew = new.filter { !missed.contains(ObjectIdentifier($0)) }
        return learning + review + missedNew + otherNew.prefix(max(newLimit - missedNew.count, 0))
    }

    /// Whether a card from a notification sent at `sentAt` is still waiting: not answered since, and
    /// still something to study today.
    static func isUnanswered(_ card: Card, sentAt: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        if let lastReview = card.lastReview, lastReview >= sentAt { return false }
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        return card.state == .new || card.due < startOfTomorrow
    }

    /// Cards from today's notifications that went out but weren't answered. They stay part of today:
    /// Study now, "Today: N cards left" and the Today screen include them until they're done.
    static func missedToday(
        from cards: [Card], sent: [PlannedReminder] = ReminderScheduler.shared.sentSoFarToday,
        now: Date = .now, calendar: Calendar = .current
    ) -> Set<ObjectIdentifier> {
        // A card sent more than once counts from the latest time.
        var lastSent: [UUID: Date] = [:]
        for reminder in sent {
            for id in reminder.cardIDs { lastSent[id] = max(lastSent[id] ?? reminder.fireDate, reminder.fireDate) }
        }
        return Set(cards.filter { card in
            guard let sentAt = card.syncID.flatMap({ lastSent[$0] }) else { return false }
            return isUnanswered(card, sentAt: sentAt, now: now, calendar: calendar)
        }.map(ObjectIdentifier.init))
    }

    /// Cards worth reviewing at some point during the day starting at `dayStart`, in study order,
    /// each paired with the earliest time it should come up.
    static func reminderCandidates(
        from cards: [Card], dayStart: Date, newLimit: Int, calendar: Calendar = .current
    ) -> [(card: Card, availableAt: Date)] {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var learning: [Card] = []
        var review: [Card] = []
        var new: [Card] = []
        for card in cards {
            switch card.state {
            case .learning, .relearning:
                if card.due < dayEnd { learning.append(card) }
            case .review:
                if card.due < dayEnd { review.append(card) }
            case .new:
                new.append(card)
            }
        }
        learning.sort { $0.due < $1.due }
        review.sort { $0.due < $1.due }
        new.sort { $0.createdAt < $1.createdAt }
        return learning.map { ($0, max($0.due, dayStart)) }
            + review.map { ($0, dayStart) }
            + new.prefix(max(newLimit, 0)).map { ($0, dayStart) }
    }

    /// New cards the user has already started today, across all folders.
    static func newCardsStudiedToday(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Int {
        let startOfDay = calendar.startOfDay(for: now)
        let newRaw = CardState.new.rawValue
        let descriptor = FetchDescriptor<ReviewLog>(
            predicate: #Predicate { $0.stateBeforeRaw == newRaw && $0.reviewedAt >= startOfDay }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    static func remainingNewCards(dailyLimit: Int, context: ModelContext, now: Date = .now) -> Int {
        max(dailyLimit - newCardsStudiedToday(context: context, now: now), 0)
    }

    /// New cards to bring in on a day: up to `remaining` (what's left of the daily setting), but only
    /// as many as that day's remaining reminders can carry after the cards already due. Each new card
    /// takes two places, since it comes back for a check a few hours after it's first seen, and must
    /// start early enough for that check to come before the day's last reminder. The rest wait for a
    /// day with room. With reminders off there's no reminder limit.
    static func newCardsThatFit(
        remaining: Int, cards: [Card], dayStart: Date, now: Date, settings: ReminderSettings,
        alreadySent: Int = 0, calendar: Calendar = .current
    ) -> Int {
        guard settings.isEnabled else { return remaining }
        let capacity = ReminderPlanner.capacity(dayStart: dayStart, now: now, settings: settings, alreadySent: alreadySent, calendar: calendar)
        let startCapacity = ReminderPlanner.capacity(
            dayStart: dayStart, now: now, settings: settings, alreadySent: alreadySent,
            until: ReminderPlanner.latestNewCardStart(dayStart: dayStart, settings: settings, calendar: calendar) ?? dayStart,
            calendar: calendar
        )
        let alreadyDue = reminderCandidates(from: cards, dayStart: dayStart, newLimit: 0, calendar: calendar).count
        return min(remaining, max(capacity - alreadyDue, 0) / 2, max(startCapacity - alreadyDue, 0))
    }

    /// The cards still to come today, which Home's "Today: N cards left" and the folder badges count.
    /// Cards reach you in notifications, so these are the cards in today's remaining ones, plus those
    /// from earlier ones you didn't answer; a card due after the last one comes in tomorrow's first.
    /// With notifications off, every card due before midnight.
    static func leftToday(from cards: [Card], newLimit: Int, now: Date = .now) -> Set<ObjectIdentifier> {
        let scheduler = ReminderScheduler.shared
        if ReminderSettings.load().isEnabled, scheduler.canSchedule {
            let planned = Set(scheduler.upcomingToday.flatMap(\.cardIDs))
            return Set(cards.filter { $0.syncID.map(planned.contains) ?? false }.map(ObjectIdentifier.init))
                .union(missedToday(from: cards, now: now))
        }
        let dayStart = Calendar.current.startOfDay(for: now)
        return Set(reminderCandidates(from: cards, dayStart: dayStart, newLimit: newLimit).map { ObjectIdentifier($0.card) })
    }

    /// Today's new cards, the same number everywhere: Home, Study now, and the reminder plan.
    static func newCardsForToday(dailyLimit: Int, context: ModelContext, now: Date = .now) -> Int {
        let remaining = remainingNewCards(dailyLimit: dailyLimit, context: context, now: now)
        let scheduler = ReminderScheduler.shared
        // Without permission to send reminders, they can't limit anything.
        guard scheduler.canSchedule else { return remaining }
        return newCardsThatFit(
            remaining: remaining, cards: comingUp(context: context),
            dayStart: Calendar.current.startOfDay(for: now), now: now, settings: ReminderSettings.load(),
            alreadySent: scheduler.sentToday.count
        )
    }
}
