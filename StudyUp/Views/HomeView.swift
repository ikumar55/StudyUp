import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.name) private var topics: [Folder]
    @Query private var allCards: [Card]
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention

    @State private var session: StudySession?
    @State private var isAddingTopic = false
    @State private var isShowingSettings = false
    @State private var topicToDelete: Folder?

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
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .fullScreenCover(item: $session) { StudySessionView(session: $0) }
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
}

#Preview {
    HomeView()
        .modelContainer(for: [Folder.self, Card.self, ReviewLog.self], inMemory: true)
}
