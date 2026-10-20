import Foundation
import SwiftData

enum StudyScope {
    case all
    case folder(Folder)
}

/// Decides which cards are ready to study right now.
enum StudyQueue {
    /// Learning cards due within this window are shown early rather than ending the session.
    static let learnAhead: TimeInterval = 20 * 60

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
                if card.due <= now.addingTimeInterval(learnAhead) { learning.append(card) }
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
}
