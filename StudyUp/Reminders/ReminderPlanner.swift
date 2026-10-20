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

    /// Spreads reminders evenly over the part of the day's active hours still ahead of `now`.
    /// - Parameter candidates: Cards in study order; each card is covered by at most one reminder.
    static func planDay<ID>(
        candidates: [Candidate<ID>], dayStart: Date, now: Date, settings: ReminderSettings
    ) -> [Reminder<ID>] {
        guard settings.isEnabled, !candidates.isEmpty,
              settings.maxPerDay > 0, settings.cardsPerReminder > 0,
              settings.endMinute > settings.startMinute
        else { return [] }

        let windowStart = dayStart.addingTimeInterval(TimeInterval(settings.startMinute * 60))
        let windowEnd = dayStart.addingTimeInterval(TimeInterval(settings.endMinute * 60))
        let earliest = max(windowStart, now.addingTimeInterval(minimumLeadTime))
        guard earliest < windowEnd else { return [] }

        // If part of the window has already passed, send proportionally fewer reminders.
        let remainingFraction = windowEnd.timeIntervalSince(earliest) / windowEnd.timeIntervalSince(windowStart)
        let cap = max(1, Int((Double(settings.maxPerDay) * remainingFraction).rounded(.up)))
        let needed = (candidates.count + settings.cardsPerReminder - 1) / settings.cardsPerReminder
        let slotCount = min(cap, needed)

        // Place each slot in the middle of its share of the window.
        let spacing = windowEnd.timeIntervalSince(earliest) / Double(slotCount)
        var used = Set<ID>()
        var reminders: [Reminder<ID>] = []
        for index in 0..<slotCount {
            let unused = candidates.filter { !used.contains($0.id) }
            var fireDate = earliest.addingTimeInterval(spacing * (Double(index) + 0.5))
            // If nothing is ready yet (e.g. only a learning card due later), wait for the next card.
            if !unused.contains(where: { $0.availableAt <= fireDate }),
               let nextReady = unused.map(\.availableAt).min(), nextReady < windowEnd {
                fireDate = max(nextReady, earliest)
            }
            let cardIDs = unused
                .filter { $0.availableAt <= fireDate }
                .prefix(settings.cardsPerReminder)
                .map(\.id)
            guard !cardIDs.isEmpty else { continue }
            used.formUnion(cardIDs)
            reminders.append(Reminder(fireDate: fireDate, cardIDs: cardIDs))
        }
        return reminders
    }
}
