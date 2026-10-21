import PhotosUI
import SwiftData
import SwiftUI

/// Adds cards to a folder (staying open for rapid entry) or edits an existing card.
struct CardEditorView: View {
    private enum Field { case front, back }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let folder: Folder?
    private let card: Card?

    @State private var front: EditableText
    @State private var back: EditableText
    @State private var addedCount = 0
    @State private var imageError: String?
    @FocusState private var focusedField: Field?

    init(folder: Folder) {
        self.folder = folder
        self.card = nil
        _front = State(initialValue: EditableText(""))
        _back = State(initialValue: EditableText(""))
    }

    init(card: Card) {
        self.folder = card.folder
        self.card = card
        _front = State(initialValue: EditableText(card.front))
        _back = State(initialValue: EditableText(card.back))
    }

    private var isNew: Bool { card == nil }

    /// A new card whose question has {{blanks}} becomes one card per blank.
    private var clozeCount: Int {
        guard isNew, Cloze.hasBlanks(front.text) else { return 0 }
        return Cloze.expand(front.text).count
    }

    /// Each side needs text or an image (an answer can be just a screenshot); a cloze needs no answer.
    private var canSave: Bool { !front.isEmpty && (!back.isEmpty || clozeCount > 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is a page fault?", text: $front.text, axis: .vertical)
                        .lineLimit(2...8)
                        .focused($focusedField, equals: .front)
                    ImageRow(images: $front.images, onError: { imageError = $0 })
                } header: {
                    Text("Question")
                } footer: {
                    if clozeCount > 0 {
                        Text("Cloze: makes \(clozeCount) \(clozeCount == 1 ? "card" : "cards"), one per blank. The answer is optional and is added as a note.")
                    } else if isNew {
                        Text("Tip: wrap words in {{double braces}} to make fill-in-the-blank cards.")
                    }
                }
                Section {
                    TextField("The answer you want to recall", text: $back.text, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($focusedField, equals: .back)
                    ImageRow(images: $back.images, onError: { imageError = $0 })
                } header: {
                    Text("Answer")
                } footer: {
                    Text("Supports **bold**, *italic*, `code` and ``` code blocks.")
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
            .alert("Couldn’t Add Image", isPresented: Binding { imageError != nil } set: { if !$0 { imageError = nil } }) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(imageError ?? "")
            }
        }
    }

    private func addAndContinue() {
        save()
        addedCount += max(clozeCount, 1)
        front = EditableText("")
        back = EditableText("")
        focusedField = .front
    }

    private func save() {
        let front = front.cardText
        let back = back.cardText
        if let card {
            card.edit(front: front, back: back)
        } else {
            let sides = Cloze.hasBlanks(front) ? Cloze.expand(front, extra: back) : [(front: front, back: back)]
            for side in sides {
                let newCard = Card(front: side.front, back: side.back)
                context.insert(newCard)
                newCard.folder = folder
            }
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

/// A card side as edited on the phone: its text with image references taken out, plus its images.
/// Unless one of them changes, the original text is kept exactly, so images placed mid-text on the
/// Mac stay where they were.
private struct EditableText {
    var text: String
    var images: [UUID]
    private let original: String
    private let originalText: String
    private let originalImages: [UUID]

    init(_ raw: String) {
        let images = ImageStore.references(in: raw)
        // Drop lines that held only an image reference; strip references left inside other lines.
        let text = raw.components(separatedBy: "\n")
            .filter { line in
                let stripped = ImageStore.replacingReferences(in: line, with: "")
                return stripped.trimmingCharacters(in: .whitespaces) != "" || line == stripped
            }
            .map { ImageStore.replacingReferences(in: $0, with: "") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text
        self.images = images
        self.original = raw
        self.originalText = text
        self.originalImages = images
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty
    }

    /// The text to store: the original if nothing changed, otherwise the text with images after it.
    var cardText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == originalText && images == originalImages { return original.trimmingCharacters(in: .whitespacesAndNewlines) }
        return images.reduce(trimmed) { ImageStore.appendingReference(to: $1, to: $0) }
    }
}

/// Thumbnails of a card side's images, with a button to add one from Photos.
private struct ImageRow: View {
    @Binding var images: [UUID]
    let onError: (String) -> Void
    @State private var picked: PhotosPickerItem?
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(images, id: \.self) { id in
                        Thumbnail(id: id) { images.removeAll { $0 == id } }
                    }
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(isLoading ? "Adding…" : "Add Image", systemImage: "photo.badge.plus")
                            .font(.subheadline)
                            .padding(.vertical, 6)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            isLoading = true
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageStore.ImageError.unreadable }
                    images.append(try ImageStore.shared.add(data))
                } catch {
                    onError(error.localizedDescription)
                }
                picked = nil
                isLoading = false
            }
        }
    }
}

private struct Thumbnail: View {
    let id: UUID
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = ImageStore.shared.url(for: id), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Remove Image", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .font(.title3)
                .offset(x: 6, y: -6)
                .buttonStyle(.borderless)
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }
}
