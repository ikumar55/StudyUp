import Foundation
import SwiftData

// Sync metadata (`syncID`, `updatedAt`, …) is optional so stores created before sync existed
// migrate automatically; `Persistence.backfillSyncMetadata` fills it in at launch.

@Model
final class Folder {
    var name: String
    var createdAt: Date
    var parent: Folder?
    /// Shared with the Mac; stable across devices.
    var syncID: UUID?
    /// Last change to the name, parent, or existence. Newest wins when syncing.
    var updatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Folder.parent)
    var subfolders: [Folder] = []

    @Relationship(deleteRule: .cascade, inverse: \Card.folder)
    var cards: [Card] = []

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.syncID = UUID()
        self.updatedAt = createdAt
    }

    /// Cards in this folder and every folder beneath it.
    var allCards: [Card] {
        cards + subfolders.flatMap(\.allCards)
    }

    /// This folder and every folder beneath it.
    var allFolders: [Folder] {
        [self] + subfolders.flatMap(\.allFolders)
    }

    var sortedSubfolders: [Folder] {
        subfolders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "OS Fundamentals › Memory"
    var path: String {
        guard let parent else { return name }
        return "\(parent.path) › \(name)"
    }

    func rename(to newName: String, now: Date = .now) {
        name = newName
        updatedAt = now
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

    var syncID: UUID?
    /// Last change to the question, answer, folder, or existence.
    var updatedAt: Date?
    /// Last change to the scheduling state above. Only this device writes it.
    var progressUpdatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.card)
    var reviewLogs: [ReviewLog] = []

    init(front: String, back: String, createdAt: Date = .now) {
        self.front = front
        self.back = back
        self.createdAt = createdAt
        self.due = createdAt
        self.syncID = UUID()
        self.updatedAt = createdAt
    }

    var state: CardState {
        CardState(rawValue: stateRaw) ?? .new
    }

    var schedule: CardSchedule {
        get {
            CardSchedule(
                state: state, due: due, stability: stability, difficulty: difficulty,
                step: step, reps: reps, lapses: lapses, lastReview: lastReview,
                fuzzSeed: syncID.map(CardSchedule.fuzzSeed)
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

    func edit(front: String, back: String, now: Date = .now) {
        self.front = front
        self.back = back
        updatedAt = now
    }

    /// Brings a studied card back into today's reviews, keeping its history ("I feel shaky on this").
    func reviewToday(now: Date = .now) {
        guard state != .new else { return }
        due = now
        progressUpdatedAt = now
    }

    /// Starts the card over as if it were new ("I've forgotten this"). Its review log is kept.
    func resetProgress(now: Date = .now) {
        schedule = CardSchedule(due: now)
        progressUpdatedAt = now
    }

    /// Applies a grade: advances the schedule and logs the review.
    func record(_ rating: Rating, fsrs: FSRS, context: ModelContext, now: Date) {
        let stateBefore = state
        schedule = fsrs.review(schedule, rating: rating, now: now)
        progressUpdatedAt = now
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
    var syncID: UUID?
    /// Whether the Mac has this log yet.
    var isSynced: Bool = false

    init(reviewedAt: Date, rating: Rating, stateBefore: CardState) {
        self.reviewedAt = reviewedAt
        self.ratingRaw = rating.rawValue
        self.stateBeforeRaw = stateBefore.rawValue
        self.syncID = UUID()
    }
}

/// Remembers a deleted folder or card until the deletion has been synced to the Mac.
@Model
final class Tombstone {
    enum Kind: String {
        case folder, card
    }

    var kindRaw: String
    var syncID: UUID
    var deletedAt: Date

    init(kind: Kind, syncID: UUID, deletedAt: Date) {
        self.kindRaw = kind.rawValue
        self.syncID = syncID
        self.deletedAt = deletedAt
    }

    var kind: Kind? { Kind(rawValue: kindRaw) }
}

extension ModelContext {
    /// Deletes a folder with everything inside it, remembering each deletion for the next sync.
    func deleteSyncing(_ folder: Folder, now: Date = .now) {
        for card in folder.allCards {
            if let syncID = card.syncID { insert(Tombstone(kind: .card, syncID: syncID, deletedAt: now)) }
        }
        for subfolder in folder.allFolders {
            if let syncID = subfolder.syncID { insert(Tombstone(kind: .folder, syncID: syncID, deletedAt: now)) }
        }
        delete(folder)
    }

    func deleteSyncing(_ card: Card, now: Date = .now) {
        if let syncID = card.syncID { insert(Tombstone(kind: .card, syncID: syncID, deletedAt: now)) }
        delete(card)
    }
}
