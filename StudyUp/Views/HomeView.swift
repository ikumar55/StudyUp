import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.name) private var topics: [Folder]
    @Query private var allCards: [Card]
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention
    @AppStorage(StudySettings.remindersEnabledKey) private var remindersEnabled = StudySettings.defaultRemindersEnabled

    @State private var session: StudySession?
    /// A reminder's session waiting for Settings to close, since only one modal can show at a time.
    @State private var queuedSession: StudySession?
    @State private var isAddingTopic = false
    @State private var isShowingSettings = false
    @State private var topicToDelete: Folder?

    private let scheduler = ReminderScheduler.shared
    private let router = NotificationRouter.shared

    var body: some View {
        let remainingNew = StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context)
        NavigationStack {
            List {
                if !allCards.isEmpty {
                    Section {
                        StudyButtonRow(counts: counts(allCards, remainingNew)) {
                            session = .make(
                                title: "All Topics", scope: .all, context: context,
                                newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention
                            )
                        }
                    } footer: {
                        if remindersEnabled, let next = scheduler.nextReminderDate {
                            Text("Next reminder \(Self.describe(next))")
                        }
                    }
                }
                if !allCards.isEmpty, remindersEnabled, scheduler.authorizationStatus == .notDetermined {
                    Section {
                        Button("Turn On Study Reminders", systemImage: "bell.badge") {
                            Task {
                                await scheduler.requestAuthorization()
                                scheduler.reschedule(context: context)
                            }
                        }
                    } footer: {
                        Text("Get a few cards at a time throughout the day, only when something is due.")
                    }
                }
                if !topics.isEmpty {
                    Section("Topics") {
                        ForEach(topics) { topic in
                            NavigationLink(value: topic) {
                                FolderRow(folder: topic, dueCount: counts(topic.allCards, remainingNew).total)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { topicToDelete = topic }
                            }
                        }
                    }
                }
            }
            .overlay {
                if topics.isEmpty { emptyState }
            }
            .navigationTitle("StudyUp")
            .navigationDestination(for: Folder.self) { FolderView(folder: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Topic", systemImage: "folder.badge.plus") { isAddingTopic = true }
                }
            }
            .folderNameAlert("New Topic", isPresented: $isAddingTopic) { name in
                context.insert(Folder(name: name))
            }
            .deleteFolderConfirmation($topicToDelete)
            .sheet(isPresented: $isShowingSettings, onDismiss: settingsDismissed) { SettingsView() }
            .fullScreenCover(item: $session, onDismiss: reschedule) { StudySessionView(session: $0) }
            .task(id: router.pendingCardID) { openPendingReminder() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No topics yet", systemImage: "books.vertical")
        } description: {
            Text("Create a topic like \"OS Fundamentals\", add subfolders for concepts, then add cards as you learn.")
        } actions: {
            Button("New Topic") { isAddingTopic = true }
                .buttonStyle(.borderedProminent)
            Button("Add Sample Cards") { SampleData.insert(into: context) }
        }
    }

    private func counts(_ cards: [Card], _ remainingNew: Int) -> StudyQueue.Counts {
        StudyQueue.counts(for: StudyQueue.build(from: cards, newLimit: remainingNew))
    }

    private func reschedule() {
        scheduler.reschedule(context: context)
    }

    /// Opens a short session starting with the card from a tapped reminder.
    private func openPendingReminder() {
        guard let cardID = router.pendingCardID else { return }
        router.pendingCardID = nil
        let card = try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.persistentModelID == cardID })).first
        let reminderSession = StudySession.make(
            title: "Quick Review", scope: .all, context: context,
            newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention,
            startingWith: card, limit: ReminderSettings.load().cardsPerReminder
        )
        if isShowingSettings {
            queuedSession = reminderSession
            isShowingSettings = false
        } else {
            session = reminderSession
        }
    }

    private func settingsDismissed() {
        reschedule()
        if let queuedSession {
            session = queuedSession
            self.queuedSession = nil
        }
    }

    /// "today at 2:15 PM" / "tomorrow at 9:45 AM"
    private static func describe(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "today at \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Folder.self, Card.self, ReviewLog.self], inMemory: true)
}
