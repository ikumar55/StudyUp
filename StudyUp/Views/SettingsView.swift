import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("New cards per day: \(newCardsPerDay)", value: $newCardsPerDay, in: 0...100)
                } footer: {
                    Text("How many never-seen cards are introduced each day. Reviews of cards you've already seen are never capped.")
                }
                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Target retention") {
                            Text(desiredRetention, format: .percent.precision(.fractionLength(0)))
                        }
                        Slider(value: $desiredRetention, in: 0.8...0.97, step: 0.01)
                    }
                } footer: {
                    Text("How likely you should be to remember a card when it comes up. Higher means more frequent reviews; 90% is a good balance.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
