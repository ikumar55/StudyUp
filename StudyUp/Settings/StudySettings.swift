import Foundation

/// UserDefaults keys and defaults for user-adjustable study settings.
enum StudySettings {
    static let newCardsPerDayKey = "newCardsPerDay"
    static let desiredRetentionKey = "desiredRetention"

    static let defaultNewCardsPerDay = 10
    static let defaultDesiredRetention = 0.9

    static func fsrs(desiredRetention: Double) -> FSRS {
        FSRS(desiredRetention: desiredRetention)
    }
}
