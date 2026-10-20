import SwiftData
import SwiftUI

struct FolderView: View {
    @Environment(\.modelContext) private var context
    let folder: Folder
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention

    @State private var session: StudySession?
    @State private var isAddingCard = false
    @State private var editingCard: Card?
    @State private var isAddingSubfolder = false
    @State private var isRenaming = false
    @State private var folderToDelete: Folder?

    var body: some View {
        let remainingNew = StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context)
        let cards = folder.cards.sorted { $0.createdAt > $1.createdAt }
        List {
            if !folder.allCards.isEmpty {
                Section {
                    StudyButtonRow(counts: counts(folder.allCards, remainingNew)) {
                        session = .make(
                            title: folder.name, scope: .folder(folder), context: context,
                            newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention
                        )
                    }
                }
            }
            if !folder.subfolders.isEmpty {
                Section("Folders") {
                    ForEach(folder.sortedSubfolders) { subfolder in
                        NavigationLink(value: subfolder) {
                            FolderRow(folder: subfolder, dueCount: counts(subfolder.allCards, remainingNew).total)
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { folderToDelete = subfolder }
                        }
                    }
                }
            }
            Section("Cards") {
                if cards.isEmpty {
                    Button("Add your first card", systemImage: "plus") { isAddingCard = true }
                } else {
                    ForEach(cards) { card in
                        Button { editingCard = card } label: { CardRow(card: card) }
                            .tint(.primary)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(cards[index]) }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Card", systemImage: "rectangle.stack.badge.plus") { isAddingCard = true }
                    Button("New Subfolder", systemImage: "folder.badge.plus") { isAddingSubfolder = true }
                    Divider()
                    Button("Rename Folder", systemImage: "pencil") { isRenaming = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .folderNameAlert("New Subfolder", isPresented: $isAddingSubfolder) { name in
            let subfolder = Folder(name: name)
            context.insert(subfolder)
            subfolder.parent = folder
        }
        .folderNameAlert("Rename Folder", isPresented: $isRenaming, initialName: folder.name) { name in
            folder.name = name
        }
        .deleteFolderConfirmation($folderToDelete)
        .sheet(isPresented: $isAddingCard) { CardEditorView(folder: folder) }
        .sheet(item: $editingCard) { CardEditorView(card: $0) }
        .fullScreenCover(item: $session) { StudySessionView(session: $0) }
    }

    private func counts(_ cards: [Card], _ remainingNew: Int) -> StudyQueue.Counts {
        StudyQueue.counts(for: StudyQueue.build(from: cards, newLimit: remainingNew))
    }
}
