import Foundation
import SwiftData

enum StudyScope {
    case all
    case folder(Folder)
}

/// Decides which cards are ready to study right now.
enum StudyQueue {

    struct Counts {
        var learning = 0
        var review = 0
        var new = 0
        var total: Int { learning + review + new }
    }

    static func cards(in scope: StudyScope, context: ModelContext) -> [Card] {
        switch scope {
        case .all: (try? context.fetch(FetchDescriptor<Card>())) ?? []
        case .folder(let folder): folder.allCards
        }
    }

    /// Learning cards first, then reviews due today, then new cards up to `newLimit`.
    static func build(from cards: [Card], newLimit: Int, now: Date = .now, calendar: Calendar = .current) -> [Card] {
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
        return learning + review + new.prefix(max(newLimit, 0))
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

    static func counts(for queue: [Card]) -> Counts {
        queue.reduce(into: Counts()) { counts, card in
            switch card.state {
            case .new: counts.new += 1
            case .review: counts.review += 1
            case .learning, .relearning: counts.learning += 1
            }
        }
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
    /// takes two places, since it comes back for a check a few hours after it's first seen. The rest
    /// wait for a day with room. With reminders off there's no reminder limit.
    static func newCardsThatFit(
        remaining: Int, cards: [Card], dayStart: Date, now: Date, settings: ReminderSettings,
        alreadySent: Int = 0, calendar: Calendar = .current
    ) -> Int {
        guard settings.isEnabled else { return remaining }
        let capacity = ReminderPlanner.capacity(dayStart: dayStart, now: now, settings: settings, alreadySent: alreadySent, calendar: calendar)
        let alreadyDue = reminderCandidates(from: cards, dayStart: dayStart, newLimit: 0, calendar: calendar).count
        return min(remaining, max(capacity - alreadyDue, 0) / 2)
    }

    /// Today's new cards, the same number everywhere: Home, Study now, and the reminder plan.
    static func newCardsForToday(dailyLimit: Int, context: ModelContext, now: Date = .now) -> Int {
        let remaining = remainingNewCards(dailyLimit: dailyLimit, context: context, now: now)
        let scheduler = ReminderScheduler.shared
        // Without permission to send reminders, they can't limit anything.
        guard scheduler.canSchedule else { return remaining }
        return newCardsThatFit(
            remaining: remaining, cards: (try? context.fetch(FetchDescriptor<Card>())) ?? [],
            dayStart: Calendar.current.startOfDay(for: now), now: now, settings: ReminderSettings.load(),
            alreadySent: scheduler.sentToday.count
        )
    }
}
