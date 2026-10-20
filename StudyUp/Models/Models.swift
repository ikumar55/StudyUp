import Foundation
import SwiftData

@Model
final class Folder {
    var name: String
    var createdAt: Date
    var parent: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var subfolders: [Folder] = []

    @Relationship(deleteRule: .cascade, inverse: \Card.folder)
    var cards: [Card] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
    }

    /// Cards in this folder and every folder beneath it.
    var allCards: [Card] {
        cards + subfolders.flatMap(\.allCards)
    }

    var sortedSubfolders: [Folder] {
        subfolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "OS Fundamentals › Memory"
    var path: String {
        guard let parent else { return name }
        return "\(parent.path) › \(name)"
    }
}

@Model
final class Card {
    var front: String
    var back: String
    var createdAt: Date
    var folder: Folder?

    // Scheduling state, stored flat so it can be used in fetch predicates.
    var stateRaw: Int = CardState.new.rawValue
    var due: Date
    var stability: Double = 0
    var difficulty: Double = 0
    var step: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var lastReview: Date?

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    var reviewLogs: [ReviewLog] = []

    init(front: String, back: String, createdAt: Date = .now) {
        self.front = front
        self.back = back
        self.createdAt = createdAt
        self.due = createdAt
    }

    var state: CardState {
        CardState(rawValue: stateRaw) ?? .new
    }

    var schedule: CardSchedule {
        get {
            CardSchedule(
                state: state, due: due, stability: stability, difficulty: difficulty,
                step: step, reps: reps, lapses: lapses, lastReview: lastReview
            )
        }
        set {
            stateRaw = newValue.state.rawValue
            due = newValue.due
            stability = newValue.stability
            difficulty = newValue.difficulty
            step = newValue.step
            reps = newValue.reps
            lapses = newValue.lapses
            lastReview = newValue.lastReview
        }
    }
}

extension Card {
    /// Applies a grade: advances the schedule and logs the review.
    func record(_ rating: Rating, fsrs: FSRS, context: ModelContext, now: Date) {
        let stateBefore = state
        schedule = fsrs.review(schedule, rating: rating, now: now)
        let log = ReviewLog(reviewedAt: now, rating: rating, stateBefore: stateBefore)
        context.insert(log)
        log.card = self
    }
}

@Model
final class ReviewLog {
    var reviewedAt: Date
    var ratingRaw: Int
    var stateBeforeRaw: Int
    var card: Card?

    init(reviewedAt: Date, rating: Rating, stateBefore: CardState) {
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.stateBeforeRaw = stateBefore.rawValue
    }
}
