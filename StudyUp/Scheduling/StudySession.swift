import Foundation
import Observation
import SwiftData

/// A run through the cards that are due, each shown once.
@Observable
final class StudySession: Identifiable {
    let title: String
    private(set) var queue: [Card]
    private(set) var reviewedCount = 0
    /// Due cards beyond this session's limit, counted when the session runs out.
    private(set) var moreDueCount = 0
    private let fsrs: FSRS
    private var refill: (() -> [Card])?
    /// Each card's review count when the session took it, so a card answered meanwhile from a
    /// notification isn't graded a second time here.
    private var repsWhenQueued: [ObjectIdentifier: Int]

    init(title: String, cards: [Card], fsrs: FSRS, refill: (() -> [Card])? = nil) {
        self.title = title
        self.queue = cards
        self.fsrs = fsrs
        self.refill = refill
        repsWhenQueued = Self.reps(of: cards)
    }

    private static func reps(of cards: [Card]) -> [ObjectIdentifier: Int] {
        Dictionary(cards.map { (ObjectIdentifier($0), $0.reps) }, uniquingKeysWith: { first, _ in first })
    }

    /// Builds a session from the cards currently due in `scope`, respecting the daily new-card limit.
    /// - Parameters:
    ///   - first: A card to show first if it's still due (e.g. the one a reminder showed).
    ///   - limit: Maximum cards before offering to keep going.
    static func make(
        title: String, scope: StudyScope, context: ModelContext,
        newCardsPerDay: Int, desiredRetention: Double,
        startingWith first: Card? = nil, limit: Int? = nil
    ) -> StudySession {
        let buildQueue = {
            let remainingNew = StudyQueue.newCardsForToday(dailyLimit: newCardsPerDay, context: context)
            return StudyQueue.build(from: StudyQueue.cards(in: scope, context: context), newLimit: remainingNew)
        }
        var queue = buildQueue()
        if let first, let index = queue.firstIndex(where: { $0 === first }) {
            queue.insert(queue.remove(at: index), at: 0)
        }
        let fsrs = StudySettings.fsrs(desiredRetention: desiredRetention)
        guard let limit, queue.count > limit else {
            return StudySession(title: title, cards: queue, fsrs: fsrs)
        }
        return StudySession(title: title, cards: Array(queue.prefix(limit)), fsrs: fsrs, refill: buildQueue)
    }

    /// A session over specific cards (e.g. a reminder's), offering everything else that's due after.
    static func make(
        title: String, cards: [Card], context: ModelContext, newCardsPerDay: Int, desiredRetention: Double
    ) -> StudySession {
        StudySession(title: title, cards: cards, fsrs: StudySettings.fsrs(desiredRetention: desiredRetention)) {
            let remainingNew = StudyQueue.newCardsForToday(dailyLimit: newCardsPerDay, context: context)
            return StudyQueue.build(from: StudyQueue.cards(in: .all, context: context), newLimit: remainingNew)
        }
    }

    var current: Card? { queue.first }

    func previews(now: Date = .now) -> [Rating: CardSchedule] {
        guard let current else { return [:] }
        return fsrs.preview(current.schedule, now: now)
    }

    func grade(_ rating: Rating, context: ModelContext, now: Date = .now) {
        guard let card = queue.first else { return }
        if card.reps == repsWhenQueued[ObjectIdentifier(card)] {
            card.record(rating, fsrs: fsrs, context: context, now: now)
        }
        // Each card is shown once per session; one you get wrong comes back in the next reminder.
        queue.removeFirst()
        reviewedCount += 1
        if queue.isEmpty, let refill {
            moreDueCount = refill().count
        }
    }

    /// Continues past the session's limit with everything else that's due.
    func keepGoing() {
        guard let refill else { return }
        queue = refill()
        repsWhenQueued = Self.reps(of: queue)
        self.refill = nil
        moreDueCount = 0
    }
}
