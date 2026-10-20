import SwiftData
import SwiftUI

@main
struct StudyUpApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        // UI tests launch with this flag so they start empty and never touch real data.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
        do {
            container = try ModelContainer(
                for: Folder.self, Card.self, ReviewLog.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
            )
        } catch {
            fatalError("Couldn't open the card database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                ReminderScheduler.shared.reschedule(context: container.mainContext)
            case .background:
                // Keep the app alive long enough to finish replacing pending reminders.
                let taskID = UIApplication.shared.beginBackgroundTask()
                let update = ReminderScheduler.shared.reschedule(context: container.mainContext)
                Task {
                    await update.value
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            default:
                break
            }
        }
    }
}
