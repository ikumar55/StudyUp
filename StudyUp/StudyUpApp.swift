import SwiftData
import SwiftUI

@main
struct StudyUpApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(Persistence.container)
        .onChange(of: scenePhase) { _, phase in
            let context = Persistence.container.mainContext
            switch phase {
            case .active:
                ReminderScheduler.shared.reschedule(context: context)
                Task { await SyncEngine.shared.sync(context: context) }
            case .background:
                // Keep the app alive long enough to sync and replace pending reminders.
                let taskID = UIApplication.shared.beginBackgroundTask()
                Task {
                    await SyncEngine.shared.sync(context: context)
                    await ReminderScheduler.shared.reschedule(context: context).value
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            default:
                break
            }
        }
    }
}
