import Foundation
import SwiftData

enum Persistence {
    static let models: [any PersistentModel.Type] = [Folder.self, Card.self, ReviewLog.self, Tombstone.self]

    /// Shared by the UI and by notification actions handled in the background.
    /// UI tests launch with -inMemoryStore so they start empty and never touch real data.
    static let container: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        do {
            let container = try makeContainer(inMemory: inMemory)
            backfillSyncMetadata(container.mainContext)
            return container
        } catch {
            fatalError("Couldn't open the card database: \(error)")
        }
    }()

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    /// Gives records created before sync existed their IDs and timestamps.
    static func backfillSyncMetadata(_ context: ModelContext) {
        let folders = (try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.syncID == nil }))) ?? []
        for folder in folders {
            folder.syncID = UUID()
            folder.updatedAt = folder.createdAt
        }
        let cards = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.syncID == nil }))) ?? []
        for card in cards {
            card.syncID = UUID()
            card.updatedAt = card.createdAt
            if card.reps > 0 { card.progressUpdatedAt = card.lastReview ?? card.createdAt }
        }
        let logs = (try? context.fetch(FetchDescriptor<ReviewLog>(predicate: #Predicate { $0.syncID == nil }))) ?? []
        for log in logs {
            log.syncID = UUID()
        }
        if !folders.isEmpty || !cards.isEmpty || !logs.isEmpty {
            try? context.save()
        }
    }
}
