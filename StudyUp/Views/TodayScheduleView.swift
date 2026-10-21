import SwiftData
import SwiftUI

/// Today's reminders: the ones still to come (with their cards) and the ones already sent.
struct TodayScheduleView: View {
    @Query private var allCards: [Card]
    @AppStorage(StudySettings.remindersEnabledKey) private var remindersEnabled = StudySettings.defaultRemindersEnabled
    private let scheduler = ReminderScheduler.shared

    var body: some View {
        let cardsByID = Dictionary(allCards.compactMap { card in card.syncID.map { ($0, card) } }, uniquingKeysWith: { first, _ in first })
        List {
            Section {
                if scheduler.upcomingToday.isEmpty {
                    Text(remindersEnabled ? "No more reminders today." : "Reminders are off. Turn them on in Settings.")
                        .foregroundStyle(.secondary)
                }
                ForEach(scheduler.upcomingToday) { reminder in
                    let cards = reminder.cardIDs.compactMap { cardsByID[$0] }
                    NavigationLink {
                        ReminderCardsView(reminder: reminder, cards: cards)
                    } label: {
                        ReminderRow(reminder: reminder, cards: cards, isSent: false)
                    }
                }
            } header: {
                Text("Coming up")
            } footer: {
                Text("The plan updates as you study: cards you review early drop out, and cards you get wrong come back later today.")
            }
            if !scheduler.sentToday.isEmpty {
                Section("Earlier today") {
                    ForEach(scheduler.sentToday.reversed()) { reminder in
                        ReminderRow(reminder: reminder, cards: reminder.cardIDs.compactMap { cardsByID[$0] }, isSent: true)
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
    let isSent: Bool

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
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Sent")
            }
        }
    }
}

/// The cards a planned reminder covers, with a way to study them now instead of waiting.
private struct ReminderCardsView: View {
    let reminder: PlannedReminder
    let cards: [Card]
    @Environment(\.modelContext) private var context
    @Environment(Presenter.self) private var presenter
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention

    var body: some View {
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
                Text("Planned for \(reminder.fireDate.formatted(date: .omitted, time: .shortened)).")
            }
            Section {
                Button("Study These Now", systemImage: "play.fill") {
                    presenter.present(.make(
                        title: "Quick Review", cards: cards, context: context,
                        newCardsPerDay: newCardsPerDay, desiredRetention: desiredRetention
                    ))
                }
                .disabled(cards.isEmpty)
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
