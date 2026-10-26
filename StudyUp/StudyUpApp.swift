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
                Task {
                    await SyncEngine.shared.sync(context: context)
                    // A throwaway test library mustn't decide which real image files are unused.
                    guard !Persistence.isInMemory else { return }
                    let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
                    ImageStore.shared.removeUnused(referenced: ImageStore.references(in: cards))
                }
            case .background:
                // Keep the app alive long enough to replace pending reminders, then sync. Reminders
                // come first: syncing can take a while (or time out) when the Mac isn't reachable.
                let background = BackgroundTask()
                let work = Task {
                    await ReminderScheduler.shared.reschedule(context: context).value
                    await SyncEngine.shared.sync(context: context)
                    background.end()
                }
                background.begin { work.cancel() }
            default:
                break
            }
        }
    }
}

/// Extra time to finish work after the app goes to the background. If iOS runs out of patience
/// first, `onExpire` runs and the task ends, so the app isn't killed for overstaying.
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    func begin(onExpire: @escaping () -> Void) {
        id = UIApplication.shared.beginBackgroundTask {
            onExpire()
            self.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
