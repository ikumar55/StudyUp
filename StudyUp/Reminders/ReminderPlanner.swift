import Foundation

/// Decides when to send reminders during one day and which cards each one covers.
/// Pure logic so it can be tested without notifications or storage.
nonisolated enum ReminderPlanner {
    struct Candidate<ID: Hashable>: Equatable {
        var id: ID
        /// The earliest moment the card is worth reviewing (e.g. a learning step's due time).
        var availableAt: Date
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
            // Spread the reminders evenly over the remaining slots...
            let target = max(Int((Double(index) + 0.5) * Double(slots.count) / Double(count)), nextSlot)
            // ...but if nothing is ready by then (e.g. a card being learned), use the first slot after it is.
            let unused = candidates.filter { !used.contains($0.id) }
            guard target < slots.count,
                  let slot = (target..<slots.count).first(where: { slot in unused.contains { $0.availableAt <= slots[slot] } })
            else { break }
            let cardIDs = unused
                .filter { $0.availableAt <= slots[slot] }
                .prefix(settings.cardsPerReminder)
                .map(\.id)
            used.formUnion(cardIDs)
            reminders.append(Reminder(fireDate: slots[slot], cardIDs: cardIDs))
            nextSlot = slot + 1
        }
        return reminders
    }
}
