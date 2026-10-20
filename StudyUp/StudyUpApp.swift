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
            case .background:
                // Keep the app alive long enough to finish replacing pending reminders.
                let taskID = UIApplication.shared.beginBackgroundTask()
                let update = ReminderScheduler.shared.reschedule(context: context)
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
