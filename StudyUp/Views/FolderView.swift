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
        let remainingNew = StudyQueue.newCardsForToday(dailyLimit: newCardsPerDay, context: context)
        // Counted across all cards, so the badges add up to Home's "Today: N cards left".
        let leftToday = StudyQueue.leftToday(from: StudyQueue.cards(in: .all, context: context), newLimit: remainingNew)
        let cards = folder.cards.sorted { $0.createdAt > $1.createdAt }
        List {
            if !folder.allCards.isEmpty {
                Section {
                    StudyButtonRow(
                        isReady: !StudyQueue.build(from: folder.allCards, newLimit: remainingNew).isEmpty,
                        hasCardsLeftToday: FolderModes.shared.isActive(folder)
                            ? folder.allCards.contains { leftToday.contains(ObjectIdentifier($0)) } : nil,
                        readySummary: "Go through this folder's cards now"
                    ) {
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
                            FolderRow(folder: subfolder, dueCount: subfolder.allCards.count { leftToday.contains(ObjectIdentifier($0)) })
                        }
                        .contextMenu { FolderModeButtons(folder: subfolder) }
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
                    Divider()
                    FolderModeButtons(folder: folder)
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
}
