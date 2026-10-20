# StudyUp — Project Plan

## Goal

A personal iOS app for **micro-studying through the day**. I write flashcards as I learn (OS fundamentals, ML foundations, and more), organize them in nested folders, and the app sends short review prompts throughout the day. Spaced repetition decides what comes up and when, so I keep what I've learned without long study sessions.

**The one feature that matters most:** a notification arrives, I answer one to three cards in under a minute, and I'm done. Everything else supports that loop.

## Principles

- **Low friction beats features.** Reviewing from a notification and adding a card should each take seconds.
- **Retention is the metric.** Scheduling follows the research (FSRS); don't invent intervals.
- **One fact per card.** The app should nudge toward small, single-fact cards, which are easy to grade honestly.
- **Local first.** All data stays on the device, with no server and no account.

## Decisions made

| Decision | Choice | Why |
|---|---|---|
| Platform | Native iOS, SwiftUI, iOS 26.5+ | First-class notification APIs; matches the iPhone (26.5.2) |
| Storage | SwiftData, on device | Built in; models are in `StudyUp/Models/Models.swift` |
| Scheduler | FSRS-5 with Anki-style learning steps (1m, 10m; relearn 10m) | Anki's current default; fewer reviews for the same retention than SM-2 |
| Grading | Wrong / Right / Easy (FSRS Again / Good / Easy) | Chosen 2026-10-19; "Hard" adds little |
| Apple account | Free (Personal Team) | No $99/yr. The app must be reinstalled from Xcode every 7 days. No iCloud/CloudKit, and App Groups may not be available |
| Writing cards on the Mac | Markdown file in iCloud Drive, imported on the phone (phase 3) | Replaces sync, which needs the paid account |
| Bundle ID | `com.ikumar55.StudyUp` | |
| Git identity | Repo-local config pushes as `ikumar55` | The machine's default GitHub login is a different account |

## Architecture

```
StudyUp/
  Models/        SwiftData models: Folder (nested), Card (content + FSRS state), ReviewLog
  Scheduling/    FSRS (pure algorithm), StudyQueue (what's due), StudySession (a run of reviews)
  Reminders/     ReminderPlanner (pure: when and which cards), ReminderScheduler (UNUserNotificationCenter),
                 notification tap handling (AppDelegate → NotificationRouter → HomeView)
  Settings/      UserDefaults keys and defaults
  Support/       Formatting, Markdown text, sample data
  Views/         Home, Folder, CardEditor, StudySession, Settings
StudyUpTests/    Unit tests (Swift Testing)
StudyUpUITests/  UI smoke test (XCTest); launches with -inMemoryStore
```

- `FSRS` and `CardSchedule` don't depend on storage, so the algorithm can be unit-tested on plain values.
- Scheduling fields are stored flat on `Card` so fetch predicates can filter on `due` and `stateRaw`.
- Queue order: learning cards due within 20 minutes, then reviews due today, then new cards up to the daily limit.

## Phases

### Phase 1: Core app ✅ (2026-10-20)
- [x] Nested folders: create, rename, delete with confirmation
- [x] Card add and edit, with rapid "add and start next" entry and inline Markdown
- [x] FSRS-5 scheduler with learning and relearning steps
- [x] Study sessions for all topics or one folder; Wrong/Right/Easy buttons show the next interval
- [x] Settings: new cards per day, target retention
- [x] Unit tests (scheduler, queue) and a UI smoke test

### Phase 2: Notifications (the core loop)
**2a: Scheduled reminders** ✅ (2026-10-20)
- [x] Notification permission prompt (from the home screen, plus a toggle in Settings)
- [x] Reminder settings: active hours, maximum reminders per day, cards per reminder
- [x] Planner: spread today's and tomorrow's due cards across active hours; skip when nothing is due
- [x] Each notification shows a real question; tapping it opens a short session starting with that card
- [x] Reschedule whenever the app opens, goes to the background, finishes a session, or changes settings
- [x] "Keep going" after a short session; "Next reminder at …" on the home screen; a test-reminder button
- Known gap: tapping a reminder while a sheet is open inside a folder (the card editor, or a folder's study session) doesn't open the review. Settings is handled. Fix: present all sessions from one place.

**2b: Answer from the notification**
- [ ] Notification Content Extension: long-press a reminder to reveal the answer
- [ ] Wrong/Right/Easy action buttons, handled in the background without opening the app
- [ ] Background refresh (BGAppRefreshTask), so reminders stay current even if the app isn't opened

### Phase 3: Quality of life
- [ ] Markdown file import, including from iCloud Drive (for writing cards on the Mac), without duplicates
- [ ] Export and backup (JSON or Markdown), which matters with free provisioning
- [ ] Rich content: code blocks, LaTeX for ML math, images
- [ ] Cloze cards ("A page fault occurs when ___")
- [ ] Search across all cards; move cards between folders
- [ ] Stats: reviews per day, retention per folder, streak
- [ ] Include or exclude folders from reminders; pause a folder

### Phase 4: Nice to have
- [ ] App icon (notifications currently show a placeholder)
- [ ] Home-screen widget showing the next due card
- [ ] Draft cards with an LLM from pasted notes, approved one by one
- [ ] Optimize FSRS weights from my own review history
- [ ] iCloud sync, if I get the paid developer account
- [ ] Anki `.apkg` import

## Notification design notes

- iOS keeps at most **64 pending local notifications** per app, and apps can't run code in the background on demand. So reminders are **planned ahead** (today and tomorrow) and replanned whenever the app runs.
- Number of reminders per day = min(maximum per day, due cards ÷ cards per reminder), spaced evenly across the remaining active hours.
- Each reminder names a specific card. Tapping it opens a session with that card plus up to N−1 more due cards.
- Cards marked Wrong come back through the 1m/10m steps. In the app they reappear in the same session; otherwise in the next reminder.

## Card-writing guidelines

1. One idea per card. If the answer has a list of five things, make five cards or a cloze.
2. Ask for understanding, not just definitions: "Why does X happen?" or "What breaks if Y?"
3. Keep answers short enough to check at a glance.
4. Add cards on the day you learn something, while the context is fresh.

## Development

```bash
# Unit tests
xcodebuild test -project StudyUp.xcodeproj -scheme StudyUp \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:StudyUpTests

# Everything, including the UI smoke test
xcodebuild test -project StudyUp.xcodeproj -scheme StudyUp \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

To run on the iPhone: open `StudyUp.xcodeproj`, pick the iPhone as the run destination, and press ⌘R. Repeat at least every 7 days, because of free provisioning.
