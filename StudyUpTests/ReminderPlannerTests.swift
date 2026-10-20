import Foundation
import Testing
@testable import StudyUp

struct ReminderPlannerTests {
    typealias Candidate = ReminderPlanner.Candidate<Int>

    let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
    let settings = ReminderSettings()  // 9:00–21:00, up to 8 a day, 3 cards each

    private func at(_ hour: Double) -> Date {
        dayStart.addingTimeInterval(hour * 3600)
    }

    private func readyCards(_ count: Int, at time: Date? = nil) -> [Candidate] {
        (0..<count).map { Candidate(id: $0, availableAt: time ?? dayStart) }
    }

    @Test func nothingDueMeansNoReminders() {
        #expect(ReminderPlanner.planDay(candidates: [Candidate](), dayStart: dayStart, now: dayStart, settings: settings).isEmpty)
    }

    @Test func disabledMeansNoReminders() {
        var off = settings
        off.isEnabled = false
        #expect(ReminderPlanner.planDay(candidates: readyCards(10), dayStart: dayStart, now: dayStart, settings: off).isEmpty)
    }

    @Test func manyCardsUseEveryReminderEvenlyAcrossTheWindow() {
        let plan = ReminderPlanner.planDay(candidates: readyCards(30), dayStart: dayStart, now: dayStart, settings: settings)
        #expect(plan.count == 8)
        #expect(plan.allSatisfy { $0.cardIDs.count == 3 })
        #expect(plan.first?.fireDate == at(9.75))
        #expect(plan.last?.fireDate == at(20.25))
        #expect(Set(plan.flatMap(\.cardIDs)).count == 24)
    }

    @Test func fewCardsMeanFewerReminders() {
        let plan = ReminderPlanner.planDay(candidates: readyCards(4), dayStart: dayStart, now: dayStart, settings: settings)
        #expect(plan.map(\.cardIDs) == [[0, 1, 2], [3]])
        #expect(plan.map(\.fireDate) == [at(12), at(18)])
    }

    @Test func partOfTheDayGoneMeansProportionallyFewer() {
        let now = at(15)
        let plan = ReminderPlanner.planDay(candidates: readyCards(30), dayStart: dayStart, now: now, settings: settings)
        #expect(plan.count == 4)
        #expect(plan.allSatisfy { $0.fireDate > now && $0.fireDate < at(21) })
    }

    @Test func afterActiveHoursMeansNoReminders() {
        #expect(ReminderPlanner.planDay(candidates: readyCards(5), dayStart: dayStart, now: at(22), settings: settings).isEmpty)
    }

    @Test func waitsForACardThatIsReadyLater() {
        let plan = ReminderPlanner.planDay(candidates: readyCards(1, at: at(19)), dayStart: dayStart, now: dayStart, settings: settings)
        #expect(plan.map(\.fireDate) == [at(19)])
    }

    @Test func cardReadyAfterActiveHoursIsSkipped() {
        let plan = ReminderPlanner.planDay(candidates: readyCards(1, at: at(22)), dayStart: dayStart, now: dayStart, settings: settings)
        #expect(plan.isEmpty)
    }

    @Test func respectsCardsPerReminder() {
        var single = settings
        single.cardsPerReminder = 1
        let plan = ReminderPlanner.planDay(candidates: readyCards(5), dayStart: dayStart, now: dayStart, settings: single)
        #expect(plan.count == 5)
        #expect(plan.map(\.cardIDs) == [[0], [1], [2], [3], [4]])
    }
}
