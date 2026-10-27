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
        container = try Persistence.makeContainer(inMemory: true)
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
        // Missed a moment ago: it waits for the next reminder instead of coming straight back.
        let soon = makeCard("learning soon", state: .learning, due: now.addingTimeInterval(5 * 60))
        let due = makeCard("learning due", state: .learning, due: now.addingTimeInterval(-60))
        let queue = StudyQueue.build(from: [laterToday, nextWeek, soon, due], newLimit: 10, now: now)
        #expect(queue.map(\.front) == ["learning due"])
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

    @Test func reminderCandidatesCoverWholeDay() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let learning = makeCard("learning", state: .learning, due: now.addingTimeInterval(600))
        let dueTomorrow = makeCard("review tomorrow", state: .review, due: tomorrow.addingTimeInterval(15 * 3600))
        let dueLater = makeCard("review in 3 days", state: .review, due: tomorrow.addingTimeInterval(3 * 86_400))
        let newCards = (0..<3).map { makeCard("new \($0)") }

        let candidates = StudyQueue.reminderCandidates(
            from: [dueLater, dueTomorrow, learning] + newCards, dayStart: tomorrow, newLimit: 2, calendar: calendar
        )
        #expect(candidates.map(\.card.front) == ["learning", "review tomorrow", "new 0", "new 1"])
        // Overdue learning cards and reviews due any time tomorrow are ready from the start of the day.
        #expect(candidates.allSatisfy { $0.availableAt == tomorrow })
    }

    @Test func limitedSessionOffersToKeepGoing() {
        let cards = (0..<4).map { makeCard("new \($0)") }
        let session = StudySession(title: "Test", cards: Array(cards.prefix(1)), fsrs: FSRS()) {
            cards.filter { $0.state == .new }
        }
        session.grade(.easy, context: context, now: now)
        #expect(session.current == nil)
        #expect(session.moreDueCount == 3)
        session.keepGoing()
        #expect(session.queue.count == 3)
        #expect(session.moreDueCount == 0)
    }

    @Test func newCardsStudiedTodayReducesRemaining() {
        let card = makeCard("new")
        let session = StudySession(title: "Test", cards: [card], fsrs: FSRS())
        session.grade(.good, context: context, now: now)
        #expect(StudyQueue.newCardsStudiedToday(context: context, now: now) == 1)
        #expect(StudyQueue.remainingNewCards(dailyLimit: 10, context: context, now: now) == 9)
    }

    // MARK: New cards that fit in reminders

    /// `now` is midnight in Los Angeles; reminders 9:00–21:00, up to 8 a day, 1 card each.
    private let losAngeles: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func newCardsThatFit(remaining: Int = 10, at hour: Double, reviewsDue: Int = 0, alreadySent: Int = 0, enabled: Bool = true) -> Int {
        var settings = ReminderSettings()
        settings.cardsPerReminder = 1
        settings.isEnabled = enabled
        let cards = (0..<reviewsDue).map { makeCard("review \($0)", state: .review, due: now) } + (0..<20).map { makeCard("new \($0)") }
        return StudyQueue.newCardsThatFit(
            remaining: remaining, cards: cards, dayStart: now, now: now.addingTimeInterval(hour * 3600),
            settings: settings, alreadySent: alreadySent, calendar: losAngeles
        )
    }

    @Test func newCardsFillTheRoomLeftInRemindersTwoPlacesEach() {
        // 8 places, 2 taken by reviews: 3 new cards, each seen twice.
        #expect(newCardsThatFit(at: 8, reviewsDue: 2) == 3)
        #expect(newCardsThatFit(remaining: 2, at: 8) == 2, "never more than the daily setting")
    }

    @Test func noRoomLeftMeansNewCardsWait() {
        #expect(newCardsThatFit(at: 22) == 0, "after the last reminder")
        #expect(newCardsThatFit(at: 8, reviewsDue: 8) == 0, "reviews fill every reminder")
        #expect(newCardsThatFit(at: 13, alreadySent: 6) == 1, "2 reminders left today")
    }

    /// A new card's same-day check comes 3 hours later, so it must start by 5:15 PM to be checked at 8:15 PM.
    @Test func newCardsStopStartingWhenTheirCheckWouldMissTheLastReminder() {
        #expect(newCardsThatFit(at: 16) == 1, "5:15 PM is the only reminder left early enough")
        #expect(newCardsThatFit(at: 17.5) == 0, "two reminders left, but too late for a check")
    }

    @Test func withRemindersOffTheDailySettingApplies() {
        #expect(newCardsThatFit(at: 22, enabled: false) == 10)
    }

    @Test func aCardAnsweredFromANotificationDuringASessionIsGradedOnce() {
        let card = makeCard("new")
        let session = StudySession(title: "Test", cards: [card], fsrs: FSRS())
        // The same card is answered from its notification while the session shows it.
        card.record(.good, fsrs: FSRS(), context: context, now: now)
        session.grade(.again, context: context, now: now)
        #expect(card.reps == 1)
        #expect(card.reviewLogs.count == 1)
        #expect(session.current == nil)
    }

    @Test func aSessionShowsEachCardOnce() {
        let card = makeCard("new")
        let other = makeCard("other")
        let session = StudySession(title: "Test", cards: [card, other], fsrs: FSRS())
        session.grade(.again, context: context, now: now)
        #expect(session.current === other, "a missed card waits for the next reminder")
        session.grade(.good, context: context, now: now)
        #expect(session.current == nil)
        #expect(session.reviewedCount == 2)
        #expect(card.due > now)
    }
}
