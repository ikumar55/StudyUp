import SwiftData
import SwiftUI

struct FolderView: View {
    @Environment(\.modelContext) private var context
    @Environment(Presenter.self) private var presenter
    let folder: Folder
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention

    @State private var isAddingSubfolder = false
    @State private var isRenaming = false
    @State private var folderToDelete: Folder?
    @State private var cardToDelete: Card?

    var body: some View {
        let remainingNew = StudyQueue.remainingNewCards(dailyLimit: newCardsPerDay, context: context)
        let cards = folder.cards.sorted { $0.createdAt > $1.createdAt }
        List {
            if !folder.allCards.isEmpty {
                Section {
                    StudyButtonRow(counts: counts(folder.allCards, remainingNew)) {
                        presenter.session = .make(
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
                    Button("Add your first card", systemImage: "plus") { presenter.sheet = .newCard(folder) }
                } else {
                    ForEach(cards) { card in
                        Button { presenter.sheet = .editCard(card) } label: { CardRow(card: card) }
                            .tint(.primary)
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { cardToDelete = card }
                            }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Card", systemImage: "rectangle.stack.badge.plus") { presenter.sheet = .newCard(folder) }
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
            folder.rename(to: name)
        }
        .deleteFolderConfirmation($folderToDelete)
        .deleteCardConfirmation($cardToDelete)
    }

    private func counts(_ cards: [Card], _ remainingNew: Int) -> StudyQueue.Counts {
        StudyQueue.counts(for: StudyQueue.build(from: cards, newLimit: remainingNew))
    }
}
