import SwiftData
import SwiftUI

/// "Study now": go through the cards now instead of waiting for notifications. No count, since the
/// "Today: N cards left" row (or a folder's badge) already gives one.
struct StudyButtonRow: View {
    /// Whether any card can be studied right now.
    let isReady: Bool
    /// Whether today's notifications will still bring cards (some may not be ready yet). Nil for a
    /// folder that's paused or out of focus, studied only on purpose.
    let hasCardsLeftToday: Bool?
    /// What studying covers, e.g. "Go through today's cards now".
    let readySummary: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(isReady ? Color.accentColor : waiting ? .secondary : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(!isReady)
    }

    /// Nothing is ready, but notifications will still bring cards later today.
    private var waiting: Bool { !isReady && hasCardsLeftToday == true }

    private var icon: String {
        isReady ? "play.circle.fill" : waiting ? "clock.fill" : "checkmark.circle.fill"
    }

    private var title: String {
        isReady ? "Study now" : waiting ? "Nothing to study yet" : "All caught up"
    }

    private var summary: String {
        switch (isReady, hasCardsLeftToday) {
        case (true, true), (true, nil): readySummary
        // After the day's last notification: what's ready now would come in tomorrow's first.
        case (true, false): "Get ahead on tomorrow's cards"
        case (false, true): "Cards you just answered come back later"
        case (false, _): "Nothing to study right now"
        }
    }
}

/// "Today: 8 cards left" with when the next notification is. Opens today's schedule.
struct TodaySummaryRow: View {
    let cardsLeft: Int
    let upcoming: [PlannedReminder]
    let remindersEnabled: Bool
    /// Notification permission was turned off for StudyUp in iOS Settings.
    var isBlockedInSettings = false
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
        guard remindersEnabled else { return isBlockedInSettings ? "Notifications are off in iOS Settings" : "Notifications are off" }
        if let next = upcoming.first {
            // Reads on from the line above: "Today: 3 cards left / Over 2 notifications · next at 5:15 PM".
            let time = next.fireDate.formatted(date: .omitted, time: .shortened)
            return upcoming.count == 1 ? "Next notification at \(time)" : "Over \(upcoming.count) notifications · next at \(time)"
        }
        if let nextReminder, !Calendar.current.isDateInToday(nextReminder) {
            return "No more notifications today · next \(Calendar.current.isDateInTomorrow(nextReminder) ? "tomorrow" : nextReminder.formatted(.dateTime.weekday())) at \(nextReminder.formatted(date: .omitted, time: .shortened))"
        }
        return "No more notifications today"
    }
}

/// A folder in a list. A focused folder shows a target icon and a paused one a pause icon; folders
/// none of whose cards come up (paused, or out of focus) are dimmed.
struct FolderRow: View {
    let folder: Folder
    /// The folder's cards still to come today (`StudyQueue.leftToday`), shown as a badge.
    let dueCount: Int
    private let modes = FolderModes.shared

    var body: some View {
        let isActive = modes.isActive(folder)
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .foregroundStyle(isActive ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                switch modes.mode(of: folder) {
                case .focused: Image(systemName: "scope").foregroundStyle(Color.accentColor)
                case .paused: Image(systemName: "pause.circle.fill").foregroundStyle(.secondary)
                case .normal: Image(systemName: "folder.fill").foregroundStyle(isActive ? Color.accentColor : .secondary)
                }
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
        return remaining <= 0 ? "Due now" : "Due \(DueText.comesBack(card.due))"
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
            Button(deleteLabel(folder.allCards.count), role: .destructive) {
                context.deleteSyncing(folder)
            }
        } message: { _ in
            Text("All subfolders, cards and review history inside it will be deleted.")
        }
    }

    private func deleteLabel(_ cardCount: Int) -> String {
        switch cardCount {
        case 0: "Delete Folder"
        case 1: "Delete Folder and 1 Card"
        default: "Delete Folder and \(cardCount) Cards"
        }
    }
}

struct DeleteCardConfirmation: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var card: Card?
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete this card?",
            isPresented: Binding(get: { card != nil }, set: { if !$0 { card = nil } }),
            titleVisibility: .visible,
            presenting: card
        ) { card in
            Button("Delete Card", role: .destructive) {
                context.deleteSyncing(card)
                onDelete()
            }
        } message: { _ in
            Text("Its review history will be deleted too.")
        }
    }
}

/// Pause / Focus for a folder, in its row's long-press menu and its own menu. Changing either
/// replans notifications, since it changes which cards come up.
struct FolderModeButtons: View {
    @Environment(\.modelContext) private var context
    let folder: Folder
    private let modes = FolderModes.shared

    var body: some View {
        switch modes.mode(of: folder) {
        case .normal:
            Button("Pause", systemImage: "pause.circle") { set(.paused) }
            Button("Focus", systemImage: "scope") { set(.focused) }
        case .paused:
            Button("Resume", systemImage: "play.circle") { set(.normal) }
        case .focused:
            Button("Stop Focusing", systemImage: "scope") { set(.normal) }
        }
    }

    private func set(_ mode: FolderModes.Mode) {
        modes.set(mode, for: folder)
        ReminderScheduler.shared.reschedule(context: context)
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

    func deleteCardConfirmation(_ card: Binding<Card?>, onDelete: @escaping () -> Void = {}) -> some View {
        modifier(DeleteCardConfirmation(card: card, onDelete: onDelete))
    }
}
