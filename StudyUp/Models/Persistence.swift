import Foundation
import SwiftData

enum Persistence {
    /// Shared by the UI and by notification actions handled in the background.
    /// UI tests launch with -inMemoryStore so they start empty and never touch real data.
    static let container: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        do {
            return try ModelContainer(
                for: Folder.self, Card.self, ReviewLog.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
        } catch {
            fatalError("Couldn't open the card database: \(error)")
        }
    }()
}
