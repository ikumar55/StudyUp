import SwiftData
import SwiftUI

/// Today's reminders: the ones still to come (with their cards) and the ones already sent. A sent one
/// is checked off once its cards are answered; until then it shows a dot and its cards can be studied.
struct TodayScheduleView: View {
    @Query private var allCards: [Card]
    @AppStorage(StudySettings.remindersEnabledKey) private var remindersEnabled = StudySettings.defaultRemindersEnabled
    private let scheduler = ReminderScheduler.shared

    var body: some View {
        let cardsByID = Dictionary(allCards.compactMap { card in card.syncID.map { ($0, card) } }, uniquingKeysWith: { first, _ in first })
        List {
            Section {
                if scheduler.upcomingToday.isEmpty {
                    Text(remindersEnabled ? "No more notifications today." : "Notifications are off. Turn them on in Settings.")
                        .foregroundStyle(.secondary)
                }
                ForEach(scheduler.upcomingToday) { reminder in
                    let cards = reminder.cardIDs.compactMap { cardsByID[$0] }
                    NavigationLink {
                        ReminderCardsView(reminder: reminder, cards: cards)
                    } label: {
                        ReminderRow(reminder: reminder, cards: cards)
                    }
                }
            } header: {
                Text("Coming up")
            } footer: {
                Text("The plan updates as you study: cards you review early drop out, and cards you get wrong come back later today.")
            }
            let sent = scheduler.sentSoFarToday
            if !sent.isEmpty {
                Section("Earlier today") {
                    ForEach(sent.reversed()) { reminder in
                        let cards = reminder.cardIDs.compactMap { cardsByID[$0] }
                        NavigationLink {
                            ReminderCardsView(reminder: reminder, cards: cards, isSent: true)
                        } label: {
                            ReminderRow(reminder: reminder, cards: cards, isSent: true)
                        }
                    }
                }
            }
        }
        .navigationTitle("Today")
    }
}

private struct ReminderRow: View {
    let reminder: PlannedReminder
    let cards: [Card]
    var isSent = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(reminder.fireDate.formatted(date: .omitted, time: .shortened))
                .font(.headline.monospacedDigit())
                .foregroundStyle(isSent ? .secondary : .primary)
                .frame(minWidth: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(reminder.cardIDs.count) \(reminder.cardIDs.count == 1 ? "card" : "cards")")
                    .font(.subheadline.weight(.medium))
                if !cards.isEmpty {
                    Text(cards.map { CardPreview.title($0) }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if isSent {
                if unanswered(cards, sentAt: reminder.fireDate).isEmpty {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Done")
                } else {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 9, height: 9)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        .accessibilityLabel("Not done yet")
                }
            }
        }
    }
}

/// A sent reminder's cards that still wait to be answered (and come up, see `FolderModes`).
private func unanswered(_ cards: [Card], sentAt: Date) -> [Card] {
    cards.filter { FolderModes.shared.includes($0) && StudyQueue.isUnanswered($0, sentAt: sentAt) }
}

/// The cards a reminder covers, with a way to study them now: a planned one's instead of waiting,
/// a sent one's that weren't answered.
private struct ReminderCardsView: View {
    let reminder: PlannedReminder
    let cards: [Card]
    var isSent = false
    @Environment(\.modelContext) private var context
    @Environment(Presenter.self) private var presenter
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention

    var body: some View {
        let toStudy = isSent ? unanswered(cards, sentAt: reminder.fireDate) : cards
        List {
            Section {
                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        CardRow(card: card)
                        if let path = card.folder?.path {
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } footer: {
                Text("\(isSent ? "Sent at" : "Planned for") \(reminder.fireDate.formatted(date: .omitted, time: .shortened)).")
            }
            if !(isSent && toStudy.isEmpty) {
                Section {
                    Button("Study These Now", systemImage: "play.fill") {
                        presenter.present(.make(
                            title: "Quick Review", cards: toStudy, context: context,
                            newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention
                        ))
                    }
                    .disabled(toStudy.isEmpty)
                }
            }
        }
        .navigationTitle(reminder.fireDate.formatted(date: .omitted, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum CardPreview {
    /// A card's question as a short plain line, for lists.
    static func title(_ card: Card, limit: Int = 48) -> String {
        let plain = PlainText.from(markdown: ImageStore.replacingReferences(in: card.front))
            .replacingOccurrences(of: "\n", with: " ")
        return plain.count > limit ? "\(plain.prefix(limit - 1))…" : plain
    }
}
