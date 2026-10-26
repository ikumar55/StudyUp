import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(StudySettings.newCardsPerDayKey) private var newCardsPerDay = StudySettings.defaultNewCardsPerDay
    @AppStorage(StudySettings.desiredRetentionKey) private var desiredRetention = StudySettings.defaultDesiredRetention
    @AppStorage(StudySettings.remindersEnabledKey) private var remindersEnabled = StudySettings.defaultRemindersEnabled
    @AppStorage(StudySettings.reminderStartMinuteKey) private var startMinute = StudySettings.defaultReminderStartMinute
    @AppStorage(StudySettings.reminderEndMinuteKey) private var endMinute = StudySettings.defaultReminderEndMinute
    @AppStorage(StudySettings.remindersPerDayKey) private var remindersPerDay = StudySettings.defaultRemindersPerDay
    @AppStorage(StudySettings.cardsPerReminderKey) private var cardsPerReminder = StudySettings.defaultCardsPerReminder

    @State private var testReminderMessage: String?
    private let scheduler = ReminderScheduler.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SyncSettingsView()
                    } label: {
                        LabeledContent {
                            Text(SyncEngine.shared.isPaired ? "On" : "Off")
                        } label: {
                            Label("Sync with Mac", systemImage: "laptopcomputer.and.iphone")
                        }
                    }
                } footer: {
                    Text("Write cards on your Mac in the StudyUp web app and they show up here.")
                }
                remindersSection
                if remindersEnabled, scheduler.canSchedule || scheduler.authorizationStatus == .notDetermined {
                    Section {
                        Button("Send a Test Reminder", systemImage: "bell") {
                            Task {
                                let sent = await scheduler.sendTestReminder(context: context)
                                testReminderMessage = sent ? "Sent. It arrives in 5 seconds." : "Add a card first."
                            }
                        }
                    } footer: {
                        Text(testReminderMessage ?? "Sends one reminder in 5 seconds so you can try tapping it.")
                    }
                }
                Section {
                    Stepper("New cards per day: \(newCardsPerDay)", value: $newCardsPerDay, in: 0...100)
                } header: {
                    Text("Studying")
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
            .task { await scheduler.refreshAuthorizationStatus() }
            .onChange(of: remindersEnabled) { _, enabled in
                if enabled, scheduler.authorizationStatus == .notDetermined {
                    Task { await scheduler.requestAuthorization() }
                }
            }
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Study reminders", isOn: $remindersEnabled)
            if remindersEnabled {
                DatePicker("From", selection: timeOfDay($startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: timeOfDay($endMinute), displayedComponents: .hourAndMinute)
                Stepper("Up to \(remindersPerDay) a day", value: $remindersPerDay, in: 1...20)
                Stepper(
                    "\(cardsPerReminder) \(cardsPerReminder == 1 ? "card" : "cards") per reminder",
                    value: $cardsPerReminder, in: 1...10
                )
            }
            if scheduler.authorizationStatus == .denied {
                Button("Allow Notifications in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(remindersFooter)
        }
    }

    private var remindersFooter: String {
        if scheduler.authorizationStatus == .denied {
            return "Notifications are turned off for StudyUp, so no reminders will be sent."
        }
        if remindersEnabled, endMinute <= startMinute {
            return "The end time must be after the start time."
        }
        return "Reminders are spread across these hours and only sent when cards are due."
    }

    /// Bridges minutes-after-midnight storage to a time picker.
    private func timeOfDay(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            ReminderSettings.time(minutes.wrappedValue, on: .now)
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }
}
