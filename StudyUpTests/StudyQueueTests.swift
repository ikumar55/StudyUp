import Foundation
import SwiftData
import Testing
@testable import StudyUp

@MainActor
struct StudyQueueTests {
    let container: ModelContainer
    let context: ModelContext
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainer(
            for: Folder.self, Card.self, ReviewLog.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }

    private func makeCard(_ name: String, state: CardState = .new, due: Date? = nil, in folder: Folder? = nil) -> Card {
        let card = Card(front: name, back: "", createdAt: now.addingTimeInterval(-3600))
        context.insert(card)
        card.folder = folder
        card.stateRaw = state.rawValue
        card.due = due ?? now
        return card
    }

    @Test func ordersLearningThenReviewThenNew() {
        let new = makeCard("new")
        let review = makeCard("review", state: .review, due: now.addingTimeInterval(-60))
        let learning = makeCard("learning", state: .learning, due: now)
        let queue = StudyQueue.build(from: [new, review, learning], newLimit: 10, now: now)
        #expect(queue.map(\.front) == ["learning", "review", "new"])
    }

    @Test func skipsCardsNotYetDue() {
        let laterToday = makeCard("learning later", state: .learning, due: now.addingTimeInterval(3 * 3600))
        let nextWeek = makeCard("review next week", state: .review, due: now.addingTimeInterval(7 * 86_400))
        let soon = makeCard("learning soon", state: .learning, due: now.addingTimeInterval(5 * 60))
        let queue = StudyQueue.build(from: [laterToday, nextWeek, soon], newLimit: 10, now: now)
        #expect(queue.map(\.front) == ["learning soon"])
    }

    @Test func limitsNewCards() {
        let cards = (0..<5).map { makeCard("new \($0)") }
        #expect(StudyQueue.build(from: cards, newLimit: 2, now: now).count == 2)
        #expect(StudyQueue.build(from: cards, newLimit: 0, now: now).isEmpty)
    }

    @Test func folderIncludesNestedCards() {
        let topic = Folder(name: "OS")
        let subtopic = Folder(name: "Memory")
        context.insert(topic)
        context.insert(subtopic)
        subtopic.parent = topic
        _ = makeCard("top", in: topic)
        _ = makeCard("nested", in: subtopic)
        #expect(Set(topic.allCards.map(\.front)) == ["top", "nested"])
        #expect(subtopic.path == "OS › Memory")
    }

    @Test func newCardsStudiedTodayReducesRemaining() {
        let card = makeCard("new")
        let session = StudySession(title: "Test", cards: [card], fsrs: FSRS())
        session.grade(.good, context: context, now: now)
        #expect(StudyQueue.newCardsStudiedToday(context: context, now: now) == 1)
        #expect(StudyQueue.remainingNewCards(dailyLimit: 10, context: context, now: now) == 9)
    }

    @Test func sessionRequeuesCardsDueSoon() {
        let card = makeCard("new")
        let session = StudySession(title: "Test", cards: [card], fsrs: FSRS())
        session.grade(.again, context: context, now: now)
        #expect(session.current === card)
        session.grade(.easy, context: context, now: now.addingTimeInterval(60))
        #expect(session.current == nil)
        #expect(session.reviewedCount == 2)
        #expect(card.reviewLogs.count == 2)
    }
}
