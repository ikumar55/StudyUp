import Foundation
import SwiftData

/// Converts between the local SwiftData store and sync records.
/// The rules match the Mac's (web/server/store.ts): content is newest-`updatedAt`-wins per record,
/// progress is newest-`progressUpdatedAt`-wins, and review logs are append-only.
enum SyncMerger {
    static let unfiledName = "Unfiled"

    /// The local changes made after `since`, plus every pending deletion and unsynced review log.
    static func pendingChanges(cursor: Int, since: Date, context: ModelContext) -> SyncRequest {
        let folders = ((try? context.fetch(FetchDescriptor<Folder>())) ?? [])
            .filter { ($0.updatedAt ?? .distantPast) > since }
            .compactMap { record($0) }
        let cards = ((try? context.fetch(FetchDescriptor<Card>())) ?? [])
            .filter { ($0.updatedAt ?? .distantPast) > since || ($0.progressUpdatedAt ?? .distantPast) > since }
            .compactMap { record($0) }
        let tombstones = (try? context.fetch(FetchDescriptor<Tombstone>())) ?? []
        let deletedFolders = tombstones.filter { $0.kind == .folder }.map {
            FolderRecord(id: $0.syncID, name: "", parentId: nil, createdAt: $0.deletedAt, updatedAt: $0.deletedAt, deleted: true)
        }
        let deletedCards = tombstones.filter { $0.kind == .card }.map {
            CardRecord(id: $0.syncID, folderId: nil, front: "", back: "", createdAt: $0.deletedAt, updatedAt: $0.deletedAt, deleted: true, progress: nil)
        }
        let logs = ((try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { !$0.isSynced }))) ?? [])
            .compactMap { record($0) }
        return SyncRequest(cursor: cursor, folders: folders + deletedFolders, cards: cards + deletedCards, reviewLogs: logs)
    }

    /// Clears what the Mac now has: sent deletions and review logs.
    static func markSent(_ request: SyncRequest, context: ModelContext) {
        let sentIDs = Set(request.folders.filter(\.deleted).map(\.id) + request.cards.filter(\.deleted).map(\.id))
        for tombstone in (try? context.fetch(FetchDescriptor<Tombstone>())) ?? [] where sentIDs.contains(tombstone.syncID) {
            context.delete(tombstone)
        }
        let sentLogIDs = Set(request.reviewLogs.map(\.id))
        for log in (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { !$0.isSynced }))) ?? [] {
            if let id = log.syncID, sentLogIDs.contains(id) { log.isSynced = true }
        }
    }

    /// Applies the Mac's changes. Returns whether anything changed locally.
    @discardableResult
    static func apply(_ response: SyncResponse, context: ModelContext) -> Bool {
        var folders = Dictionary(
            ((try? context.fetch(FetchDescriptor<Folder>())) ?? []).compactMap { f in f.syncID.map { ($0, f) } },
            uniquingKeysWith: { first, _ in first }
        )
        var cards = Dictionary(
            ((try? context.fetch(FetchDescriptor<Card>())) ?? []).compactMap { c in c.syncID.map { ($0, c) } },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false

        // Create and update first, then link parents, then delete, so a card moved out of
        // a folder deleted in the same sync survives the folder's cascade.
        var linkParents: [(Folder, UUID?)] = []
        for record in response.folders where !record.deleted {
            if let folder = folders[record.id] {
                guard record.updatedAt > (folder.updatedAt ?? .distantPast) else { continue }
                folder.name = record.name
                folder.updatedAt = record.updatedAt
                linkParents.append((folder, record.parentId))
            } else {
                let folder = Folder(name: record.name, createdAt: record.createdAt)
                context.insert(folder)
                folder.syncID = record.id
                folder.updatedAt = record.updatedAt
                folders[record.id] = folder
                linkParents.append((folder, record.parentId))
            }
            changed = true
        }
        for (folder, parentID) in linkParents {
            folder.parent = parentID.flatMap { folders[$0] }
        }

        for record in response.cards where !record.deleted {
            let card: Card
            if let existing = cards[record.id] {
                card = existing
            } else {
                card = Card(front: record.front, back: record.back, createdAt: record.createdAt)
                context.insert(card)
                card.syncID = record.id
                card.updatedAt = .distantPast
                cards[record.id] = card
            }
            if record.updatedAt > (card.updatedAt ?? .distantPast) {
                card.front = record.front
                card.back = record.back
                card.folder = record.folderId.flatMap { folders[$0] }
                card.updatedAt = record.updatedAt
                changed = true
            }
            if let progress = record.progress, progress.updatedAt > (card.progressUpdatedAt ?? .distantPast) {
                card.schedule = CardSchedule(
                    state: CardState(rawValue: progress.state) ?? .new, due: progress.due,
                    stability: progress.stability, difficulty: progress.difficulty, step: progress.step,
                    reps: progress.reps, lapses: progress.lapses, lastReview: progress.lastReview
                )
                card.progressUpdatedAt = progress.updatedAt
                changed = true
            }
        }

        for record in response.cards where record.deleted {
            guard let card = cards[record.id], record.updatedAt >= (card.updatedAt ?? .distantPast) else { continue }
            context.delete(card)
            cards[record.id] = nil
            changed = true
        }
        for record in response.folders where record.deleted {
            guard let folder = folders[record.id], record.updatedAt >= (folder.updatedAt ?? .distantPast) else { continue }
            context.delete(folder)
            folders[record.id] = nil
            changed = true
        }

        // A card can lose its folder when the folder is deleted on one side after the card was
        // moved into it on the other. Rehome it so it stays visible; the move syncs back.
        let orphans = cards.values.filter { $0.folder == nil }
        if !orphans.isEmpty {
            let unfiled = folders.values.first { $0.parent == nil && $0.name == unfiledName } ?? {
                let folder = Folder(name: unfiledName)
                context.insert(folder)
                return folder
            }()
            for card in orphans {
                card.folder = unfiled
                card.updatedAt = .now
            }
            changed = true
        }

        // Review history only comes back on a first sync, e.g. after reinstalling the app.
        if !response.reviewLogs.isEmpty {
            let known = Set(((try? context.fetch(FetchDescriptor<ReviewLog>())) ?? []).compactMap(\.syncID))
            for record in response.reviewLogs where !known.contains(record.id) {
                guard let card = cards[record.cardId] else { continue }
                let log = ReviewLog(
                    reviewedAt: record.reviewedAt, rating: Rating(rawValue: record.rating) ?? .good,
                    stateBefore: CardState(rawValue: record.stateBefore) ?? .new
                )
                context.insert(log)
                log.syncID = record.id
                log.isSynced = true
                log.card = card
                changed = true
            }
        }
        return changed
    }

    // MARK: - Records

    static func record(_ folder: Folder) -> FolderRecord? {
        guard let id = folder.syncID else { return nil }
        return FolderRecord(
            id: id, name: folder.name, parentId: folder.parent?.syncID,
            createdAt: folder.createdAt, updatedAt: folder.updatedAt ?? folder.createdAt, deleted: false
        )
    }

    static func record(_ card: Card) -> CardRecord? {
        guard let id = card.syncID else { return nil }
        let progress = card.progressUpdatedAt.map { updatedAt in
            ProgressRecord(
                state: card.stateRaw, due: card.due, stability: card.stability, difficulty: card.difficulty,
                step: card.step, reps: card.reps, lapses: card.lapses, lastReview: card.lastReview, updatedAt: updatedAt
            )
        }
        return CardRecord(
            id: id, folderId: card.folder?.syncID, front: card.front, back: card.back,
            createdAt: card.createdAt, updatedAt: card.updatedAt ?? card.createdAt, deleted: false, progress: progress
        )
    }

    static func record(_ log: ReviewLog) -> ReviewLogRecord? {
        guard let id = log.syncID, let cardID = log.card?.syncID else { return nil }
        return ReviewLogRecord(id: id, cardId: cardID, reviewedAt: log.reviewedAt, rating: log.ratingRaw, stateBefore: log.stateBeforeRaw)
    }
}
