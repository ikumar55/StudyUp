import Foundation
import SwiftData
import Testing
@testable import StudyUp

@MainActor
struct SyncMergerTests {
    let container: ModelContainer
    let context: ModelContext
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func makeFolder(_ name: String, parent: Folder? = nil, at time: Date? = nil) -> Folder {
        let folder = Folder(name: name, createdAt: time ?? t0)
        context.insert(folder)
        folder.parent = parent
        return folder
    }

    private func makeCard(_ front: String, in folder: Folder, at time: Date? = nil) -> Card {
        let card = Card(front: front, back: "answer", createdAt: time ?? t0)
        context.insert(card)
        card.folder = folder
        return card
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: - Sending

    @Test func firstSyncSendsEverythingWithRelationships() {
        let os = makeFolder("OS")
        let memory = makeFolder("Memory", parent: os)
        let card = makeCard("What is a TLB?", in: memory)
        card.record(.good, fsrs: FSRS(), context: context, now: at(60))

        let request = SyncMerger.pendingChanges(cursor: 0, since: .distantPast, context: context)
        #expect(Set(request.folders.map(\.id)) == [os.syncID!, memory.syncID!])
        #expect(request.folders.first { $0.id == memory.syncID }?.parentId == os.syncID)
        #expect(request.cards.count == 1)
        #expect(request.cards[0].folderId == memory.syncID)
        #expect(request.cards[0].progress?.reps == 1)
        #expect(request.reviewLogs.map(\.cardId) == [card.syncID!])
    }

    @Test func onlyChangesSinceTheLastSyncAreSent() {
        let os = makeFolder("OS", at: at(0))
        let old = makeCard("Old", in: os, at: at(0))
        let edited = makeCard("Edited", in: os, at: at(0))
        edited.edit(front: "Edited again", back: "answer", now: at(200))
        let studied = makeCard("Studied", in: os, at: at(0))
        studied.record(.again, fsrs: FSRS(), context: context, now: at(300))

        let request = SyncMerger.pendingChanges(cursor: 5, since: at(100), context: context)
        #expect(request.cursor == 5)
        #expect(request.folders.isEmpty)
        #expect(Set(request.cards.map(\.front)) == ["Edited again", "Studied"])
        #expect(!request.cards.contains { $0.id == old.syncID })
    }

    @Test func deletingAFolderSendsTombstonesForEverythingInside() {
        let os = makeFolder("OS")
        let memory = makeFolder("Memory", parent: os)
        let card = makeCard("Q", in: memory)
        let ids = (os.syncID!, memory.syncID!, card.syncID!)
        context.deleteSyncing(os, now: at(500))

        let request = SyncMerger.pendingChanges(cursor: 0, since: at(400), context: context)
        #expect(Set(request.folders.filter(\.deleted).map(\.id)) == [ids.0, ids.1])
        #expect(request.cards.filter(\.deleted).map(\.id) == [ids.2])
        #expect(request.cards.allSatisfy { $0.updatedAt == at(500) })

        SyncMerger.markSent(request, context: context)
        #expect(fetchAll(Tombstone.self).isEmpty)
    }

    @Test func markSentFlagsReviewLogs() {
        let card = makeCard("Q", in: makeFolder("OS"))
        card.record(.good, fsrs: FSRS(), context: context, now: at(10))
        let request = SyncMerger.pendingChanges(cursor: 0, since: .distantPast, context: context)
        SyncMerger.markSent(request, context: context)
        #expect(SyncMerger.pendingChanges(cursor: 0, since: .distantPast, context: context).reviewLogs.isEmpty)
    }

    // MARK: - Receiving

    @Test func appliesNewFoldersAndCardsFromTheMac() {
        let os = FolderRecord(id: UUID(), name: "OS", parentId: nil, createdAt: t0, updatedAt: t0, deleted: false)
        let memory = FolderRecord(id: UUID(), name: "Memory", parentId: os.id, createdAt: t0, updatedAt: t0, deleted: false)
        let card = CardRecord(
            id: UUID(), folderId: memory.id, front: "What is a page fault?", back: "A trap…",
            createdAt: t0, updatedAt: t0, deleted: false, progress: nil
        )
        // The child comes before its parent, as it can from the Mac.
        let changed = SyncMerger.apply(SyncResponse(cursor: 3, folders: [memory, os], cards: [card], reviewLogs: []), context: context)

        #expect(changed)
        let folders = fetchAll(Folder.self)
        let memoryFolder = folders.first { $0.syncID == memory.id }
        #expect(memoryFolder?.path == "OS › Memory")
        let cards = fetchAll(Card.self)
        #expect(cards.count == 1)
        #expect(cards[0].folder === memoryFolder)
        #expect(cards[0].state == .new)
    }

    @Test func olderEditsFromTheMacDontOverwriteNewerLocalOnes() {
        let os = makeFolder("OS")
        let card = makeCard("Local", in: os)
        card.edit(front: "Edited on phone", back: "answer", now: at(200))
        var record = SyncMerger.record(card)!
        record.front = "Edited on Mac"
        record.updatedAt = at(100)

        SyncMerger.apply(SyncResponse(cursor: 1, folders: [], cards: [record], reviewLogs: []), context: context)
        #expect(card.front == "Edited on phone")

        record.updatedAt = at(300)
        SyncMerger.apply(SyncResponse(cursor: 2, folders: [], cards: [record], reviewLogs: []), context: context)
        #expect(card.front == "Edited on Mac")
    }

    @Test func newerProgressReplacesTheSchedule() {
        let card = makeCard("Q", in: makeFolder("OS"))
        var record = SyncMerger.record(card)!
        record.progress = ProgressRecord(
            state: CardState.review.rawValue, due: at(86_400 * 4), stability: 4.5, difficulty: 5.2,
            step: 0, reps: 3, lapses: 1, lastReview: at(0), updatedAt: at(50)
        )
        SyncMerger.apply(SyncResponse(cursor: 1, folders: [], cards: [record], reviewLogs: []), context: context)
        #expect(card.state == .review)
        #expect(card.reps == 3)
        #expect(card.due == at(86_400 * 4))
        #expect(card.progressUpdatedAt == at(50))
    }

    @Test func aResetFromTheMacMakesTheCardNewAgain() {
        let card = makeCard("Q", in: makeFolder("OS"))
        card.record(.good, fsrs: FSRS(), context: context, now: at(0))
        card.record(.good, fsrs: FSRS(), context: context, now: at(600))
        #expect(card.state == .review)
        var record = SyncMerger.record(card)!
        record.progress = ProgressRecord(
            state: 0, due: at(900), stability: 0, difficulty: 0, step: 0, reps: 0, lapses: 0, lastReview: nil, updatedAt: at(900)
        )
        SyncMerger.apply(SyncResponse(cursor: 2, folders: [], cards: [record], reviewLogs: []), context: context)
        #expect(card.state == .new)
        #expect(card.reps == 0)
        #expect(card.reviewLogs.count == 2, "history is kept")
    }

    @Test func deletionsFromTheMacRemoveLocalRecords() {
        let os = makeFolder("OS")
        let keep = makeFolder("Keep")
        let movedOut = makeCard("Moved out before the delete", in: os)
        let deletedCard = makeCard("Deleted", in: keep)

        var folderRecord = SyncMerger.record(os)!
        folderRecord.deleted = true
        folderRecord.updatedAt = at(100)
        var moveRecord = SyncMerger.record(movedOut)!
        moveRecord.folderId = keep.syncID
        moveRecord.updatedAt = at(90)
        var deleteRecord = SyncMerger.record(deletedCard)!
        deleteRecord.deleted = true
        deleteRecord.updatedAt = at(100)

        SyncMerger.apply(
            SyncResponse(cursor: 4, folders: [folderRecord], cards: [deleteRecord, moveRecord], reviewLogs: []),
            context: context
        )
        #expect(fetchAll(Folder.self).map(\.name) == ["Keep"])
        #expect(fetchAll(Card.self).map(\.front) == ["Moved out before the delete"])
        // Deletions that came from the Mac aren't echoed back.
        #expect(fetchAll(Tombstone.self).isEmpty)
    }

    @Test func cardsLeftWithoutAFolderGoToUnfiled() {
        let orphan = CardRecord(
            id: UUID(), folderId: UUID(), front: "Folder was deleted elsewhere", back: "A",
            createdAt: t0, updatedAt: t0, deleted: false, progress: nil
        )
        let beforeApply = Date.now
        SyncMerger.apply(SyncResponse(cursor: 1, folders: [], cards: [orphan], reviewLogs: []), context: context)
        let card = try! #require(fetchAll(Card.self).first)
        #expect(card.folder?.name == SyncMerger.unfiledName)
        #expect(card.folder?.parent == nil)
        // The move is a local edit, so it's sent on the next sync.
        #expect(SyncMerger.pendingChanges(cursor: 1, since: beforeApply, context: context).cards.map(\.id) == [orphan.id])
    }

    @Test func restoresReviewHistoryOnce() {
        let card = makeCard("Q", in: makeFolder("OS"))
        let log = ReviewLogRecord(id: UUID(), cardId: card.syncID!, reviewedAt: at(10), rating: 3, stateBefore: 0)
        let response = SyncResponse(cursor: 1, folders: [], cards: [], reviewLogs: [log])
        SyncMerger.apply(response, context: context)
        SyncMerger.apply(response, context: context)
        #expect(card.reviewLogs.count == 1)
        #expect(card.reviewLogs[0].isSynced)
    }

    @Test func roundTripsThroughJSONAsMilliseconds() throws {
        let card = CardRecord(
            id: UUID(), folderId: nil, front: "Q", back: "A", createdAt: t0, updatedAt: at(1.5),
            deleted: false, progress: nil
        )
        let data = try SyncCoding.encoder.encode(card)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["updatedAt"] as? Double == (t0.timeIntervalSince1970 + 1.5) * 1000)
        #expect(try SyncCoding.decoder.decode(CardRecord.self, from: data) == card)
    }
}
