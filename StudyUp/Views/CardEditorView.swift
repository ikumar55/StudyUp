import SwiftData
import SwiftUI

/// Adds cards to a folder (staying open for rapid entry) or edits an existing card.
struct CardEditorView: View {
    private enum Field { case front, back }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let folder: Folder?
    private let card: Card?

    @State private var front: String
    @State private var back: String
    @State private var addedCount = 0
    @FocusState private var focusedField: Field?

    init(folder: Folder) {
        self.folder = folder
        self.card = nil
        _front = State(initialValue: "")
        _back = State(initialValue: "")
    }

    init(card: Card) {
        self.folder = card.folder
        self.card = card
        _front = State(initialValue: card.front)
        _back = State(initialValue: card.back)
    }

    private var isNew: Bool { card == nil }

    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("What is a page fault?", text: $front, axis: .vertical)
                        .lineLimit(2...8)
                        .focused($focusedField, equals: .front)
                }
                Section {
                    TextField("The answer you want to recall", text: $back, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($focusedField, equals: .back)
                } header: {
                    Text("Answer")
                } footer: {
                    Text("Supports **bold**, *italic* and `code`.")
                }
                if isNew {
                    Section {
                        Button("Add and Start Next Card", systemImage: "plus.circle.fill", action: addAndContinue)
                            .disabled(!canSave)
                    } footer: {
                        if addedCount > 0, let folder {
                            Text("Added \(addedCount) \(addedCount == 1 ? "card" : "cards") to \(folder.name).")
                        }
                    }
                } else if let card {
                    Section("Progress") {
                        LabeledContent("Status", value: statusText(card))
                        LabeledContent("Reviews", value: "\(card.reps)")
                        LabeledContent("Times forgotten", value: "\(card.lapses)")
                    }
                    Section {
                        Button("Delete Card", role: .destructive) {
                            context.deleteSyncing(card)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(addedCount > 0 ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        save()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if isNew { focusedField = .front }
            }
        }
    }

    private func addAndContinue() {
        save()
        addedCount += 1
        front = ""
        back = ""
        focusedField = .front
    }

    private func save() {
        let front = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = back.trimmingCharacters(in: .whitespacesAndNewlines)
        if let card {
            card.edit(front: front, back: back)
        } else {
            let newCard = Card(front: front, back: back)
            context.insert(newCard)
            newCard.folder = folder
        }
    }

    private func statusText(_ card: Card) -> String {
        switch card.state {
        case .new: return "New"
        case .learning, .relearning: return "Learning"
        case .review:
            let remaining = card.due.timeIntervalSinceNow
            return remaining <= 0 ? "Due now" : "Next review in \(IntervalText.short(remaining))"
        }
    }
}
