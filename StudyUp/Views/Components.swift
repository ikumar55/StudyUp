import SwiftData
import SwiftUI

/// "Study now" row showing how many cards are waiting.
struct StudyButtonRow: View {
    let counts: StudyQueue.Counts
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: counts.total > 0 ? "play.circle.fill" : "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(counts.total > 0 ? Color.accentColor : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(counts.total > 0 ? "Study now" : "All caught up")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(counts.total == 0)
    }

    private var summary: String {
        guard counts.total > 0 else { return "Nothing to study right now" }
        let ready = "\(counts.total) \(counts.total == 1 ? "card" : "cards") ready now"
        return counts.new > 0 ? "\(ready), \(counts.new) new" : ready
    }
}

/// "Today: 8 cards left" with when the next reminder is. Opens today's schedule.
struct TodaySummaryRow: View {
    let cardsLeft: Int
    let upcoming: [PlannedReminder]
    let remindersEnabled: Bool
    let nextReminder: Date?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: cardsLeft == 0 ? "checkmark.circle.fill" : "calendar")
                .font(.title2)
                .foregroundStyle(cardsLeft == 0 ? Color.green : Color.accentColor)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(cardsLeft == 0 ? "All done for today" : "Today: \(cardsLeft) \(cardsLeft == 1 ? "card" : "cards") left")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        guard remindersEnabled else { return "Reminders are off" }
        if let next = upcoming.first {
            let count = upcoming.count
            return "\(count) \(count == 1 ? "reminder" : "reminders") left · next at \(next.fireDate.formatted(date: .omitted, time: .shortened)) (\(next.cardIDs.count) \(next.cardIDs.count == 1 ? "card" : "cards"))"
        }
        if let nextReminder, !Calendar.current.isDateInToday(nextReminder) {
            return "No more reminders today · next \(Calendar.current.isDateInTomorrow(nextReminder) ? "tomorrow" : nextReminder.formatted(.dateTime.weekday())) at \(nextReminder.formatted(date: .omitted, time: .shortened))"
        }
        return "No more reminders today"
    }
}

struct FolderRow: View {
    let folder: Folder
    let dueCount: Int

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "folder.fill")
            }
            Spacer()
            if dueCount > 0 {
                Text("\(dueCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var subtitle: String {
        let cardCount = folder.allCards.count
        let folderCount = folder.subfolders.count
        var parts = ["\(cardCount) \(cardCount == 1 ? "card" : "cards")"]
        if folderCount > 0 { parts.append("\(folderCount) \(folderCount == 1 ? "folder" : "folders")") }
        return parts.joined(separator: " · ")
    }
}

struct CardRow: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarkdownText(ImageStore.replacingReferences(in: card.front))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        if card.state == .new { return "New" }
        let remaining = card.due.timeIntervalSinceNow
        return remaining <= 0 ? "Due now" : "Due \(DueText.next(card.due))"
    }
}

/// Text-field alert for naming or renaming a folder.
struct FolderNameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    var initialName: String
    let onSave: (String) -> Void
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onSave(trimmed) }
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented { name = initialName }
            }
    }
}

/// Confirms before deleting a folder, since it removes everything inside it.
struct DeleteFolderConfirmation: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var folder: Folder?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \"\(folder?.name ?? "")\"?",
            isPresented: Binding(get: { folder != nil }, set: { if !$0 { folder = nil } }),
            titleVisibility: .visible,
            presenting: folder
        ) { folder in
            Button("Delete Folder and \(folder.allCards.count) Cards", role: .destructive) {
                context.deleteSyncing(folder)
            }
        } message: { _ in
            Text("All subfolders, cards and review history inside it will be deleted.")
        }
    }
}

extension View {
    func folderNameAlert(
        _ title: String, isPresented: Binding<Bool>, initialName: String = "", onSave: @escaping (String) -> Void
    ) -> some View {
        modifier(FolderNameAlert(title: title, isPresented: isPresented, initialName: initialName, onSave: onSave))
    }

    func deleteFolderConfirmation(_ folder: Binding<Folder?>) -> some View {
        modifier(DeleteFolderConfirmation(folder: folder))
    }
}
