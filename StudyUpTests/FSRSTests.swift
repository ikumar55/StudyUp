import Foundation
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
        let at = start.addingTimeInterval(600)
        return (fsrs.review(first, rating: .good, now: at), at)
    }

    @Test func newCardAgainGoesToFirstLearningStep() {
        let next = fsrs.review(newCard(), rating: .again, now: start)
        #expect(next.state == .learning)
        #expect(next.step == 0)
        #expect(next.due == start.addingTimeInterval(60))
        #expect(next.reps == 1)
        #expect(next.lastReview == start)
    }

    @Test func newCardGoodGoesToSecondLearningStep() {
        let next = fsrs.review(newCard(), rating: .good, now: start)
        #expect(next.state == .learning)
        #expect(next.step == 1)
        #expect(next.due == start.addingTimeInterval(600))
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
        let next = fsrs.review(first, rating: .again, now: start.addingTimeInterval(600))
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
        #expect(next.due == card.due.addingTimeInterval(600))

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
}
