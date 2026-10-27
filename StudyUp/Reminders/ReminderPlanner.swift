import Foundation

/// Decides when to send reminders during one day and which cards each one covers.
/// Pure logic so it can be tested without notifications or storage.
nonisolated enum ReminderPlanner {
    struct Candidate<ID: Hashable>: Equatable {
        var id: ID
        /// The earliest moment the card is worth reviewing (e.g. a learning step's due time).
        var availableAt: Date
        /// The latest reminder the card may go in, if any (a new card needs room for its same-day check).
        var latestAt: Date? = nil

        func fits(_ slot: Date) -> Bool {
            availableAt <= slot && latestAt.map { slot <= $0 } ?? true
        }
    }

    struct Reminder<ID: Hashable>: Equatable {
        var fireDate: Date
        /// Cards this reminder covers; the first one is shown in the notification.
        var cardIDs: [ID]
    }

    /// Reminders won't be scheduled sooner than this after planning.
    static let minimumLeadTime: TimeInterval = 60

    /// The times reminders can go out on a day: `maxPerDay` fixed slots, each in the middle of its
    /// share of the active hours. Fixed, so replanning never moves a reminder or squeezes in extra ones.
    static func slots(dayStart: Date, settings: ReminderSettings, calendar: Calendar = .current) -> [Date] {
        guard settings.maxPerDay > 0, settings.endMinute > settings.startMinute else { return [] }
        let windowStart = ReminderSettings.time(settings.startMinute, on: dayStart, calendar: calendar)
        let windowEnd = ReminderSettings.time(settings.endMinute, on: dayStart, calendar: calendar)
        let spacing = windowEnd.timeIntervalSince(windowStart) / Double(settings.maxPerDay)
        return (0..<settings.maxPerDay).map { windowStart.addingTimeInterval(spacing * (Double($0) + 0.5)) }
    }

    /// How long after a new card is first answered Right it comes back for its same-day check.
    static let newCardCheckDelay: TimeInterval = FSRS.defaultLearningSteps.dropFirst().first ?? 0

    /// The last reminder a new card can start in, leaving a later one for its same-day check.
    static func latestNewCardStart(dayStart: Date, settings: ReminderSettings, calendar: Calendar = .current) -> Date? {
        slots(dayStart: dayStart, settings: settings, calendar: calendar).last?.addingTimeInterval(-newCardCheckDelay)
    }

    /// How many cards the day's reminders still ahead of `now` (and no later than `until`) can carry, all told.
    static func capacity(
        dayStart: Date, now: Date, settings: ReminderSettings, alreadySent: Int = 0, until: Date? = nil,
        calendar: Calendar = .current
    ) -> Int {
        guard settings.isEnabled else { return 0 }
        let earliest = now.addingTimeInterval(minimumLeadTime)
        let slotsLeft = slots(dayStart: dayStart, settings: settings, calendar: calendar)
            .filter { slot in slot >= earliest && until.map { slot <= $0 } ?? true }.count
        return max(min(slotsLeft, settings.maxPerDay - alreadySent), 0) * max(settings.cardsPerReminder, 0)
    }

    /// Picks which of the day's slots still ahead of `now` get a reminder, and the cards for each.
    /// - Parameters:
    ///   - candidates: Cards in study order; each card is covered by at most one reminder.
    ///   - alreadySent: Reminders that already went out that day; they count toward `maxPerDay`.
    static func planDay<ID>(
        candidates: [Candidate<ID>], dayStart: Date, now: Date, settings: ReminderSettings,
        alreadySent: Int = 0, calendar: Calendar = .current
    ) -> [Reminder<ID>] {
        guard settings.isEnabled, !candidates.isEmpty, settings.cardsPerReminder > 0 else { return [] }
        let earliest = now.addingTimeInterval(minimumLeadTime)
        let slots = slots(dayStart: dayStart, settings: settings, calendar: calendar).filter { $0 >= earliest }
        let needed = (candidates.count + settings.cardsPerReminder - 1) / settings.cardsPerReminder
        let count = min(slots.count, settings.maxPerDay - alreadySent, needed)
        guard count > 0 else { return [] }

        var used = Set<ID>()
        var reminders: [Reminder<ID>] = []
        var nextSlot = 0
        for index in 0..<count {
            let unused = candidates.filter { !used.contains($0.id) }
            // Spread the reminders evenly over the remaining slots...
            var target = max(Int((Double(index) + 0.5) * Double(slots.count) / Double(count)), nextSlot)
            // ...keeping the ones for cards with a latest time (new cards, which come last in study order
            // and so fill the last reminders) early enough for each to get a slot in time...
            let limited = nextSlot < slots.count ? unused.filter { $0.latestAt.map { slots[nextSlot] <= $0 } ?? false } : []
            if let latest = limited.compactMap(\.latestAt).min(), let lastFit = slots.lastIndex(where: { $0 <= latest }) {
                let limitedReminders = (limited.count + settings.cardsPerReminder - 1) / settings.cardsPerReminder
                let isLimited = limitedReminders >= count - index
                target = min(target, max(lastFit - limitedReminders + (isLimited ? 1 : 0), nextSlot))
            }
            // ...but if nothing is ready by then (e.g. a card being learned), use the first slot after it is.
            guard target < slots.count,
                  let slot = (target..<slots.count).first(where: { slot in unused.contains { $0.fits(slots[slot]) } })
            else { break }
            let cardIDs = unused
                .filter { $0.fits(slots[slot]) }
                .prefix(settings.cardsPerReminder)
                .map(\.id)
            used.formUnion(cardIDs)
            reminders.append(Reminder(fireDate: slots[slot], cardIDs: cardIDs))
            nextSlot = slot + 1
        }
        return reminders
    }
}
