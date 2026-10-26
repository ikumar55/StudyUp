import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.name) private var topics: [Folder]
    @Query private var allCards: [Card]
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention
    @AppStorage(StudySettings.remindersEnabledKey) private var remindersEnabled = StudySettings.defaultRemindersEnabled

    @State private var presenter = Presenter()
    @State private var isAddingTopic = false
    @State private var topicToDelete: Folder?

    private let scheduler = ReminderScheduler.shared
    private let router = NotificationRouter.shared

    var body: some View {
        let remainingNew = StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context)
        NavigationStack {
            List {
                if !allCards.isEmpty {
                    Section {
                        NavigationLink {
                            TodayScheduleView()
                        } label: {
                            TodaySummaryRow(
                                cardsLeft: dueToday(remainingNew).count,
                                upcoming: scheduler.upcomingToday,
                                remindersEnabled: remindersEnabled && scheduler.canSchedule,
                                nextReminder: scheduler.nextReminderDate
                            )
                        }
                        StudyButtonRow(counts: counts(allCards, remainingNew)) {
                            presenter.session = .make(
                                title: "All Topics", scope: .all, context: context,
                                newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention
                            )
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
                    Button("Settings", systemImage: "gearshape") { presenter.sheet = .settings }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Topic", systemImage: "folder.badge.plus") { isAddingTopic = true }
                }
            }
            .folderNameAlert("New Topic", isPresented: $isAddingTopic) { name in
                context.insert(Folder(name: name))
            }
            .deleteFolderConfirmation($topicToDelete)
        }
        .environment(presenter)
        .sheet(item: $presenter.sheet, onDismiss: sheetDismissed) { sheet in
            Group {
                switch sheet {
                case .settings: SettingsView()
                case .newCard(let folder): CardEditorView(folder: folder)
                case .editCard(let card): CardEditorView(card: card)
                }
            }
            .environment(presenter)
        }
        .fullScreenCover(item: $presenter.session, onDismiss: reschedule) { StudySessionView(session: $0) }
        .onChange(of: presenter.session == nil) { _, isClosed in router.isStudying = !isClosed }
        .task(id: router.pendingReminder) { openPendingReminder() }
        // Adding sample cards or deleting a folder changes what's due without closing a sheet.
        .onChange(of: allCards.count) { reschedule() }
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

    private func sheetDismissed() {
        reschedule()
        presenter.sheetDismissed()
    }

    /// Every card still to study today: due reviews, cards being learned, and today's new cards.
    private func dueToday(_ remainingNew: Int) -> [Card] {
        StudyQueue.reminderCandidates(from: allCards, dayStart: Calendar.current.startOfDay(for: .now), newLimit: remainingNew)
            .map(\.card)
    }

    /// Opens a short session with exactly the cards a tapped reminder was planned for (those still
    /// due today). Older reminders without that list start with their card and fill up from what's due.
    private func openPendingReminder() {
        guard let tap = router.pendingReminder else { return }
        router.pendingReminder = nil
        let remainingNew = StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context)
        let stillDue = Set(dueToday(remainingNew).map(ObjectIdentifier.init))
        let byID = Dictionary(allCards.compactMap { card in card.syncID.map { ($0, card) } }, uniquingKeysWith: { first, _ in first })
        let planned = tap.cardIDs.compactMap { byID[$0] }.filter { stillDue.contains(ObjectIdentifier($0)) }
        if !planned.isEmpty {
            presenter.present(.make(
                title: "Quick Review", cards: planned, context: context,
                newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention
            ))
            return
        }
        let cardID = tap.cardID
        let card = try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.persistentModelID == cardID })).first
        presenter.present(.make(
            title: "Quick Review", scope: .all, context: context,
            newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention,
            startingWith: card, limit: ReminderSettings.load().cardsPerReminder
        ))
    }
}

#Preview {
    HomeView()
        .modelContainer(try! Persistence.makeContainer(inMemory: true))
}
