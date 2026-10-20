import SwiftData
import SwiftUI

@main
struct StudyUpApp: App {
    /// UI tests launch with this flag so they start empty and never touch real data.
    private let usesInMemoryStore = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [Folder.self, Card.self, ReviewLog.self], inMemory: usesInMemoryStore)
    }
}
