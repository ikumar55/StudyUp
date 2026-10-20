import Foundation
import Observation
import SwiftData

/// A run through the cards that are due, re-showing cards that come back within the session.
@Observable
final class StudySession: Identifiable {
    let title: String
    private(set) var queue: [Card]
    private(set) var reviewedCount = 0
    private let fsrs: FSRS

    init(title: String, cards: [Card], fsrs: FSRS) {
        self.title = title
        self.queue = cards
        self.fsrs = fsrs
    }

    /// Builds a session from the cards currently due in `scope`, respecting the daily new-card limit.
    static func make(
        title: String, scope: StudyScope, context: ModelContext,
        newCardsPerDay: Int, desiredRetention: Double
    ) -> StudySession {
        let remainingNew = StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context)
        let queue = StudyQueue.build(from: StudyQueue.cards(in: scope, context: context), newLimit: remainingNew)
        return StudySession(title: title, cards: queue, fsrs: StudySettings.fsrs(desiredRetention: desiredRetention))
    }

    var current: Card? { queue.first }

    func previews(now: Date = .now) -> [Rating: CardSchedule] {
        guard let current else { return [:] }
        return fsrs.preview(current.schedule, now: now)
    }

    func grade(_ rating: Rating, context: ModelContext, now: Date = .now) {
        guard let card = queue.first else { return }
        let stateBefore = card.state
        card.schedule = fsrs.review(card.schedule, rating: rating, now: now)

        let log = ReviewLog(reviewedAt: now, rating: rating, stateBefore: stateBefore)
        context.insert(log)
        log.card = card

        queue.removeFirst()
        reviewedCount += 1
        if card.due <= now.addingTimeInterval(StudyQueue.learnAhead) {
            queue.append(card)
        }
    }
}
