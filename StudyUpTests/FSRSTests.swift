import Foundation
import SwiftData
import Testing
@testable import StudyUp

struct FSRSTests {
    let fsrs = FSRS()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    private func newCard() -> CardSchedule {
        CardSchedule(due: start)
    }

    /// Runs a new card through its learning steps until it reaches the review state.
    private func graduated() -> (card: CardSchedule, at: Date) {
        let first = fsrs.review(newCard(), rating: .good, now: start)
        let at = first.due
        return (fsrs.review(first, rating: .good, now: at), at)
    }

    @Test func newCardAgainGoesToFirstLearningStep() {
        let next = fsrs.review(newCard(), rating: .again, now: start)
        #expect(next.state == .learning)
        #expect(next.step == 0)
        // 15 minutes: long enough to land in the next reminder rather than this one.
        #expect(next.due == start.addingTimeInterval(15 * 60))
        #expect(next.reps == 1)
        #expect(next.lastReview == start)
    }

    @Test func newCardGoodGoesToSecondLearningStep() {
        let next = fsrs.review(newCard(), rating: .good, now: start)
        #expect(next.state == .learning)
        #expect(next.step == 1)
        // A same-day check a few hours later.
        #expect(next.due == start.addingTimeInterval(3 * 3600))
        #expect(abs(next.stability - FSRS.defaultWeights[2]) < 1e-9)
    }

    @Test func newCardEasyGraduatesImmediately() {
        let next = fsrs.review(newCard(), rating: .easy, now: start)
        #expect(next.state == .review)
        // Initial Easy stability is ~15.7 days, and at 90% retention the interval equals stability.
        #expect(next.due == start.addingTimeInterval(16 * day))
    }

    @Test func finishingLearningStepsGraduates() {
        let (card, at) = graduated()
        #expect(card.state == .review)
        #expect(card.step == 0)
        #expect(card.due >= at.addingTimeInterval(day))
        #expect(card.stability >= FSRS.defaultWeights[2])
    }

    @Test func againDuringLearningRestartsSteps() {
        let first = fsrs.review(newCard(), rating: .good, now: start)
        let next = fsrs.review(first, rating: .again, now: first.due)
        #expect(next.state == .learning)
        #expect(next.step == 0)
        #expect(next.stability < first.stability)
    }

    @Test func successfulReviewIncreasesStability() {
        let (card, _) = graduated()
        let reviewTime = card.due
        let next = fsrs.review(card, rating: .good, now: reviewTime)
        #expect(next.state == .review)
        #expect(next.stability > card.stability)
        let previousInterval = card.due.timeIntervalSince(card.lastReview!)
        #expect(next.due.timeIntervalSince(reviewTime) > previousInterval)
    }

    @Test func forgettingAReviewCardEntersRelearning() {
        let (card, _) = graduated()
        let next = fsrs.review(card, rating: .again, now: card.due)
        #expect(next.state == .relearning)
        #expect(next.lapses == 1)
        #expect(next.stability < card.stability)
        #expect(next.difficulty > card.difficulty)
        #expect(next.due == card.due.addingTimeInterval(15 * 60))

        let relearned = fsrs.review(next, rating: .good, now: next.due)
        #expect(relearned.state == .review)
        #expect(relearned.lapses == 1)
    }

    @Test func easyAlwaysOutlastsGood() {
        let (card, _) = graduated()
        let previews = fsrs.preview(card, now: card.due)
        #expect(previews[.easy]!.due > previews[.good]!.due)
        #expect(previews[.good]!.due > previews[.again]!.due)
    }

    @Test func difficultyStaysInRange() {
        var card = graduated().card
        var now = card.due
        for _ in 0..<20 {
            card = fsrs.review(card, rating: .again, now: now)
            now = now.addingTimeInterval(day)
        }
        #expect(card.difficulty <= 10)
        for _ in 0..<40 {
            card = fsrs.review(card, rating: .easy, now: now)
            now = card.due
        }
        #expect(card.difficulty >= 1)
    }

    @Test func higherRetentionMeansShorterIntervals() {
        let strict = FSRS(desiredRetention: 0.97)
        let relaxed = FSRS(desiredRetention: 0.8)
        #expect(strict.intervalDays(stability: 10) < fsrs.intervalDays(stability: 10))
        #expect(relaxed.intervalDays(stability: 10) > fsrs.intervalDays(stability: 10))
        #expect(fsrs.intervalDays(stability: 10) == 10)
    }

    @Test func retrievabilityAtStabilityIsNinetyPercent() {
        #expect(abs(fsrs.retrievability(elapsedDays: 7, stability: 7) - 0.9) < 1e-9)
    }

    // MARK: Fuzz

    /// Fuzzed intervals for many different cards.
    private func fuzzedForManyCards(_ days: Int, reps: Int = 2) -> Set<Int> {
        Set((0..<500).map { _ in FSRS.fuzzed(days, seed: CardSchedule.fuzzSeed(for: UUID()), reps: reps, maximum: 36_500) })
    }

    @Test func fuzzStaysWithinAnkisRanges() {
        #expect(fuzzedForManyCards(4) == [3, 4, 5])
        #expect(fuzzedForManyCards(14) == Set(12...16))
        #expect(fuzzedForManyCards(16) == Set(13...19))
        #expect(fuzzedForManyCards(44) == Set(40...48))
    }

    @Test func shortIntervalsAndUnseededCardsAreNotFuzzed() {
        #expect(fuzzedForManyCards(1) == [1])
        #expect(fuzzedForManyCards(2) == [2])
        #expect(FSRS.fuzzed(44, seed: nil, reps: 2, maximum: 36_500) == 44)
        #expect(FSRS.fuzzed(44, seed: 7, reps: 2, maximum: 42) <= 42)
    }

    @Test func fuzzIsFixedPerCardAndReview() {
        let seed = CardSchedule.fuzzSeed(for: UUID())
        #expect(FSRS.fuzzed(44, seed: seed, reps: 3, maximum: 36_500) == FSRS.fuzzed(44, seed: seed, reps: 3, maximum: 36_500))
        // Each review of a card gets its own nudge.
        let byReview = Set((0..<50).map { FSRS.fuzzed(44, seed: seed, reps: $0, maximum: 36_500) })
        #expect(byReview.count > 1)
    }

    @Test func cardsLearnedTogetherComeDueOnDifferentDays() {
        let graduations = (0..<30).map { _ in
            var card = newCard()
            card.fuzzSeed = CardSchedule.fuzzSeed(for: UUID())
            return fsrs.review(card, rating: .easy, now: start).due
        }
        #expect(Set(graduations).count > 1)
        #expect(graduations.allSatisfy { $0 >= start.addingTimeInterval(13 * day) && $0 <= start.addingTimeInterval(19 * day) })
    }

    @Test func theButtonLabelMatchesWhatGradingDoes() {
        var card = graduated().card
        card.fuzzSeed = CardSchedule.fuzzSeed(for: UUID())
        let shownAt = card.due
        let previews = fsrs.preview(card, now: shownAt)
        for rating in Rating.allCases {
            #expect(fsrs.review(card, rating: rating, now: shownAt) == previews[rating])
        }
        #expect(previews[.easy]!.due > previews[.good]!.due)
    }
}

@MainActor
struct CardProgressActionTests {
    @Test func reviewTodayMakesAStudiedCardDueKeepingItsMemory() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let card = Card(front: "Q", back: "A")
        container.mainContext.insert(card)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        card.record(.easy, fsrs: FSRS(), context: container.mainContext, now: start)
        let stability = card.stability
        #expect(card.due > start.addingTimeInterval(86_400))

        let now = start.addingTimeInterval(3600)
        card.reviewToday(now: now)
        #expect(card.due == now)
        #expect(card.state == .review)
        #expect(card.stability == stability)
        #expect(card.progressUpdatedAt == now)
    }

    @Test func resetStartsOverAsNew() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let card = Card(front: "Q", back: "A")
        container.mainContext.insert(card)
        card.record(.good, fsrs: FSRS(), context: container.mainContext, now: .now)
        card.resetProgress()
        #expect(card.state == .new)
        #expect(card.reps == 0)
        #expect(card.stability == 0)
        #expect(card.reviewLogs.count == 1)
    }

    @Test func reviewTodayLeavesNewCardsAlone() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let card = Card(front: "Q", back: "A", createdAt: Date(timeIntervalSince1970: 0))
        container.mainContext.insert(card)
        card.reviewToday()
        #expect(card.progressUpdatedAt == nil)
    }
}

struct DueTextTests {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // a weekday morning, UTC

    private func later(days: Double) -> Date { now.addingTimeInterval(days * 86_400) }

    @Test func sameDayDependsOnTheAnswer() {
        let morning = calendar.startOfDay(for: now).addingTimeInterval(9 * 3600)
        #expect(DueText.next(morning.addingTimeInterval(15 * 60), from: morning, rating: .again, calendar: calendar) == "next notification")
        #expect(DueText.next(morning.addingTimeInterval(3 * 3600), from: morning, rating: .good, calendar: calendar) == "in a few hours")
        // A card's status, rather than an answer, just says it's later today.
        #expect(DueText.next(morning.addingTimeInterval(3 * 3600), from: morning, calendar: calendar) == "later today")
    }

    /// A check due after the day's last notification (8:15 PM) arrives in tomorrow's first one,
    /// even though it's due before the notification hours end at 9 PM.
    @Test func aCheckAfterTheLastNotificationIsTomorrow() {
        let today = calendar.startOfDay(for: now)
        let lastReminder = today.addingTimeInterval(20.25 * 3600)
        let at = { (hour: Double) in today.addingTimeInterval(hour * 3600) }
        // Right at 5:59 PM: the 3-hour check is due at 8:59 PM, after the last notification.
        #expect(DueText.next(at(20.98), from: at(17.98), rating: .good, lastReminder: lastReminder, calendar: calendar) == "tomorrow")
        // Right at 5:00 PM: due at 8:00 PM, in time for the 8:15 PM notification.
        #expect(DueText.next(at(20), from: at(17), rating: .good, lastReminder: lastReminder, calendar: calendar) == "in a few hours")
        #expect(DueText.next(at(20.97), from: at(20.72), rating: .again, lastReminder: lastReminder, calendar: calendar) == "next notification")
        // A card's status says the same.
        #expect(DueText.next(at(20.98), from: at(18), lastReminder: lastReminder, calendar: calendar) == "tomorrow")
        #expect(DueText.next(at(20), from: at(18), lastReminder: lastReminder, calendar: calendar) == "later today")
    }

    @Test func daysWeeksMonthsYears() {
        #expect(DueText.next(later(days: 1), from: now, calendar: calendar) == "tomorrow")
        #expect(DueText.next(later(days: 4), from: now, calendar: calendar) == "in 4 days")
        #expect(DueText.next(later(days: 16), from: now, calendar: calendar) == "in 2 weeks")
        #expect(DueText.next(later(days: 75), from: now, calendar: calendar) == "in 2 months")
        #expect(DueText.next(later(days: 365), from: now, calendar: calendar) == "in 1 year")
        #expect(DueText.next(later(days: 550), from: now, calendar: calendar) == "in 1.5 years")
    }
}
