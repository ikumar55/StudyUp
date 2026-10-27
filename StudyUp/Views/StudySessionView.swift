import SwiftData
import SwiftUI

struct StudySessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let session: StudySession
    @State private var isRevealed = false

    var body: some View {
        NavigationStack {
            Group {
                if let card = session.current {
                    cardView(card)
                } else {
                    finishedView
                }
            }
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if session.current != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Text("\(session.queue.count) left")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let path = card.folder?.path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    CardContentView(text: card.front, style: .title2, weight: .semibold)
                    if isRevealed {
                        Divider()
                        CardContentView(text: card.back, style: .title3)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .contentShape(Rectangle())
            .onTapGesture { reveal() }

            controls
                .padding()
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isRevealed {
            let now = Date.now
            let previews = session.previews(now: now)
            HStack(spacing: 10) {
                gradeButton(.again, title: "Wrong", color: .red, preview: previews[.again], now: now)
                gradeButton(.good, title: "Right", color: .green, preview: previews[.good], now: now)
                gradeButton(.easy, title: "Easy", color: .blue, preview: previews[.easy], now: now)
            }
        } else {
            Button(action: reveal) {
                Text("Show Answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func gradeButton(_ rating: Rating, title: String, color: Color, preview: CardSchedule?, now: Date) -> some View {
        Button {
            session.grade(rating, context: context)
            try? context.save()
            // So a reminder planned for this card doesn't go off while you're still studying.
            ReminderScheduler.shared.rescheduleSoon(context: context)
            isRevealed = false
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                if let preview {
                    Text(DueText.next(preview.due, from: now, rating: rating, lastReminder: ReminderSettings.load().lastReminder(on: now)))
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
    }

    private var finishedView: some View {
        ContentUnavailableView {
            Label("All caught up", systemImage: "checkmark.circle.fill")
        } description: {
            Text(session.reviewedCount == 0
                 ? "Nothing is due right now."
                 : "You reviewed \(session.reviewedCount) \(session.reviewedCount == 1 ? "card" : "cards").")
        } actions: {
            if session.moreDueCount > 0 {
                Button("Keep Going (\(session.moreDueCount) more)") { session.keepGoing() }
                    .buttonStyle(.borderedProminent)
                Button("Done") { dismiss() }
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func reveal() {
        withAnimation(.easeOut(duration: 0.2)) { isRevealed = true }
    }
}
