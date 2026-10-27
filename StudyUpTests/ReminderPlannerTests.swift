import Foundation
import Testing
@testable import StudyUp

struct ReminderPlannerTests {
    typealias Candidate = ReminderPlanner.Candidate<Int>

    /// Midnight, 2027-01-15, in Los Angeles. Slots for the default settings fall at
    /// 9:45, 11:15, 12:45, 14:15, 15:45, 17:15, 18:45 and 20:15.
    let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
    let settings = ReminderSettings()  // 9:00–21:00, up to 8 a day, 3 cards each
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func at(_ hour: Double) -> Date {
        dayStart.addingTimeInterval(hour * 3600)
    }

    private func readyCards(_ count: Int, at time: Date? = nil) -> [Candidate] {
        (0..<count).map { Candidate(id: $0, availableAt: time ?? dayStart) }
    }

    private func plan(
        _ candidates: [Candidate], now: Date? = nil, settings: ReminderSettings? = nil, alreadySent: Int = 0
    ) -> [ReminderPlanner.Reminder<Int>] {
        ReminderPlanner.planDay(
            candidates: candidates, dayStart: dayStart, now: now ?? dayStart, settings: settings ?? self.settings,
            alreadySent: alreadySent, calendar: calendar
        )
    }

    @Test func nothingDueMeansNoReminders() {
        #expect(plan([]).isEmpty)
    }

    @Test func disabledMeansNoReminders() {
        var off = settings
        off.isEnabled = false
        #expect(plan(readyCards(10), settings: off).isEmpty)
    }

    @Test func manyCardsUseEveryReminderEvenlyAcrossTheWindow() {
        let plan = plan(readyCards(30))
        #expect(plan.count == 8)
        #expect(plan.allSatisfy { $0.cardIDs.count == 3 })
        #expect(plan.first?.fireDate == at(9.75))
        #expect(plan.last?.fireDate == at(20.25))
        #expect(Set(plan.flatMap(\.cardIDs)).count == 24)
    }

    @Test func fewCardsMeanFewerRemindersSpreadOut() {
        let plan = plan(readyCards(4))
        #expect(plan.map(\.cardIDs) == [[0, 1, 2], [3]])
        #expect(plan.map(\.fireDate) == [at(12.75), at(18.75)])
    }

    @Test func partOfTheDayGoneMeansOnlyTheSlotsLeft() {
        let now = at(15)
        let plan = plan(readyCards(30), now: now)
        #expect(plan.map(\.fireDate) == [at(15.75), at(17.25), at(18.75), at(20.25)])
    }

    @Test func remindersAlreadySentCountTowardTheDailyMaximum() {
        let plan = plan(readyCards(30), now: at(12), alreadySent: 6)
        #expect(plan.count == 2)
        #expect(self.plan(readyCards(30), now: at(12), alreadySent: 8).isEmpty)
    }

    /// The bug this guards against: each replan (after every answer) treated the rest of the day
    /// as a fresh day, so "up to 8" became 16 or more, bunched up in the evening.
    @Test func answeringEachReminderAndReplanningNeverExceedsTheDailyMaximum() {
        var cards = readyCards(40)
        var sent: [Date] = []
        var now = dayStart
        while let next = plan(cards, now: now, alreadySent: sent.count).first {
            sent.append(next.fireDate)
            cards.removeAll { next.cardIDs.contains($0.id) }
            now = next.fireDate.addingTimeInterval(2 * 60)
        }
        #expect(sent == [9.75, 11.25, 12.75, 14.25, 15.75, 17.25, 18.75, 20.25].map(at))
    }

    @Test func replanningKeepsTheSameTimes() {
        let before = plan(readyCards(30)).dropFirst().map(\.fireDate)
        let after = plan(readyCards(30), now: at(10), alreadySent: 1).map(\.fireDate)
        #expect(after == Array(before))
    }

    @Test func afterActiveHoursMeansNoReminders() {
        #expect(plan(readyCards(5), now: at(22)).isEmpty)
    }

    @Test func aCardReadyLaterGoesInTheNextReminderAfterIt() {
        #expect(plan(readyCards(1, at: at(19))).map(\.fireDate) == [at(20.25)])
    }

    @Test func cardReadyAfterTheLastReminderIsSkipped() {
        #expect(plan(readyCards(1, at: at(20.5))).isEmpty)
    }

    @Test func respectsCardsPerReminder() {
        var single = settings
        single.cardsPerReminder = 1
        let plan = plan(readyCards(5), settings: single)
        #expect(plan.count == 5)
        #expect(plan.map(\.cardIDs) == [[0], [1], [2], [3], [4]])
    }

    @Test(arguments: [(2026, 11, 1), (2027, 3, 14)])
    func activeHoursKeepTheirClockTimesWhenTheClocksChange(year: Int, month: Int, day: Int) {
        let dayStart = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let slots = ReminderPlanner.slots(dayStart: dayStart, settings: settings, calendar: calendar)
        let times = slots.map { calendar.dateComponents([.hour, .minute], from: $0) }
        #expect(times.first?.hour == 9 && times.first?.minute == 45)
        #expect(times.last?.hour == 20 && times.last?.minute == 15)
        #expect(settings.lastReminder(on: dayStart.addingTimeInterval(12 * 3600), calendar: calendar) == slots.last)
    }

    // MARK: New cards need room for their same-day check

    private func newCards(_ count: Int, from first: Int = 100) -> [Candidate] {
        let latest = ReminderPlanner.latestNewCardStart(dayStart: dayStart, settings: settings, calendar: calendar)
        return (first..<first + count).map { Candidate(id: $0, availableAt: dayStart, latestAt: latest) }
    }

    @Test func newCardsStartNoLaterThanThreeHoursBeforeTheLastReminder() {
        #expect(ReminderPlanner.latestNewCardStart(dayStart: dayStart, settings: settings, calendar: calendar) == at(17.25))
    }

    /// Spread evenly, the last of these would go out at 8:15 PM, leaving no notification for its check.
    @Test func newCardsAreSpreadOnlyAsLateAsTheirChecksAllow() {
        var single = settings
        single.cardsPerReminder = 1
        let plan = plan(readyCards(2) + newCards(3), settings: single)
        #expect(plan.map(\.cardIDs) == [[0], [1], [100], [101], [102]])
        #expect(plan.map(\.fireDate) == [at(9.75), at(12.75), at(14.25), at(15.75), at(17.25)])
    }

    @Test func aNewCardTooLateForItsCheckWaitsForTomorrow() {
        #expect(plan(newCards(1), now: at(17.5)).isEmpty)
        #expect(plan(readyCards(1) + newCards(1), now: at(17.5)).map(\.cardIDs) == [[0]])
    }
}
