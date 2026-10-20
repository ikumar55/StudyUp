import Foundation

/// UserDefaults keys and defaults for user-adjustable study settings.
nonisolated enum StudySettings {
    static let newCardsPerDayKey = "newCardsPerDay"
    static let desiredRetentionKey = "desiredRetention"
    static let remindersEnabledKey = "remindersEnabled"
    static let reminderStartMinuteKey = "reminderStartMinute"
    static let reminderEndMinuteKey = "reminderEndMinute"
    static let remindersPerDayKey = "remindersPerDay"
    static let cardsPerReminderKey = "cardsPerReminder"

    static let defaultNewCardsPerDay = 10
    static let defaultDesiredRetention = 0.9
    static let defaultRemindersEnabled = true
    static let defaultReminderStartMinute = 9 * 60
    static let defaultReminderEndMinute = 21 * 60
    static let defaultRemindersPerDay = 8
    static let defaultCardsPerReminder = 3

    static func fsrs(desiredRetention: Double) -> FSRS {
        FSRS(desiredRetention: desiredRetention)
    }

    static func newCardsPerDay(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: newCardsPerDayKey) as? Int ?? defaultNewCardsPerDay
    }

    static func desiredRetention(_ defaults: UserDefaults = .standard) -> Double {
        defaults.object(forKey: desiredRetentionKey) as? Double ?? defaultDesiredRetention
    }
}

nonisolated struct ReminderSettings: Equatable, Sendable {
    var isEnabled = StudySettings.defaultRemindersEnabled
    /// Active hours as minutes after midnight.
    var startMinute = StudySettings.defaultReminderStartMinute
    var endMinute = StudySettings.defaultReminderEndMinute
    var maxPerDay = StudySettings.defaultRemindersPerDay
    var cardsPerReminder = StudySettings.defaultCardsPerReminder

    static func load(_ defaults: UserDefaults = .standard) -> ReminderSettings {
        var settings = ReminderSettings()
        if let value = defaults.object(forKey: StudySettings.remindersEnabledKey) as? Bool { settings.isEnabled = value }
        if let value = defaults.object(forKey: StudySettings.reminderStartMinuteKey) as? Int { settings.startMinute = value }
        if let value = defaults.object(forKey: StudySettings.reminderEndMinuteKey) as? Int { settings.endMinute = value }
        if let value = defaults.object(forKey: StudySettings.remindersPerDayKey) as? Int { settings.maxPerDay = value }
        if let value = defaults.object(forKey: StudySettings.cardsPerReminderKey) as? Int { settings.cardsPerReminder = value }
        return settings
    }
}
