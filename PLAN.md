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
| Writing cards on the Mac | Local web app on the Mac (TypeScript: React UI + Node server + SQLite) that syncs with the phone over Wi-Fi (phase 3) | Chosen 2026-10-20 over a phone-hosted editor: you can write anytime, the Mac keeps a backup, and it can move to the cloud later by hosting the same server |
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
StudyUpNotificationContent/  Notification Content Extension: question + answer on long-press; reads the app's payload keys
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
- [x] All sheets and sessions are presented from one place (`Presenter`), so a reminder tap always opens its review

**2b: Answer from the notification** ✅ (2026-10-20)
- [x] Wrong/Right/Easy action buttons, handled in the background without opening the app
- [x] Stale reminders (card reviewed or deleted since) are cleared from Notification Center; stale grades are ignored
- [x] Notification Content Extension (`StudyUpNotificationContent/`): long-press shows the answer; buttons show intervals ("Right · 3d")
- [x] Plan up to 7 days ahead within the 64-notification limit, so reminders keep coming even if the app isn't opened. This replaced BGAppRefreshTask, which iOS runs unpredictably.

### Phase 3: Mac web app and sync ✅ (2026-10-20, built and tested on simulator and Mac; device testing pending)
**3a: Phone foundations**
- [x] Stable IDs (UUID), `updatedAt` timestamps, and delete tombstones on folders and cards, migrated safely for existing data (optional fields, backfilled at launch)
- [x] Info.plist keys for local networking (`Config/StudyUp-Info.plist`, merged with Xcode's generated plist)

**3b: Mac server** (`web/server`)
- [x] Node + TypeScript server with a SQLite database at `~/Library/Application Support/StudyUp/` (Node's built-in `node:sqlite`; Hono for HTTP)
- [x] REST API for the web UI (this Mac only), plus `/pair` and `/sync` for the phone
- [x] Advertised on the network over Bonjour (`_studyup._tcp`, with host and port in the TXT record); one-time 6-digit pairing code (burned after 5 wrong tries); sync requires the paired token
- [x] Starts automatically at login (launchd agent): `web/scripts/install-service.sh` copies the app to Application Support, since background services can't read ~/Desktop

**3c: Sync**
- [x] Phone discovers the Mac (or takes a typed address), then syncs on app open, on app close, and from Sync Now
- [x] Content (folders, questions, answers) syncs both ways, with the newest edit winning per record
- [x] Review progress and logs are owned by the phone and uploaded, so the Mac always has a full backup; a first sync after reinstalling restores them
- [x] Deletes propagate via tombstones; a sync cursor means only changes are sent
- [x] Sync status on the phone (Settings → Sync with Mac)
- [x] Cards left without a folder by a conflicting delete are moved into an "Unfiled" topic, which syncs back

**3d: Web UI** (`web/client`, React + Vite) ✅ (2026-10-20, built and checked in headless Chrome; not yet tried in Safari)
- [x] Folder tree with create, rename, move (menu or drag-and-drop) and delete, plus keyboard navigation
- [x] Fast card entry (⌘↩ adds the card and returns to Question), inline editing, live Markdown preview, delete with Undo
- [x] Bulk paste: `Q:`/`A:` blocks, `question :: answer` lines, or tab-separated, with live preview and skipped-line warnings
- [x] Search across all cards (⌘K); move cards between folders
- [x] Download a backup (JSON); iPhone pairing panel; live updates when the phone syncs (polls every 3 s)

### Phase 3.5: Quality of life
- [ ] Rich content: code blocks, LaTeX for ML math, images (in both the app and the web UI)
- [ ] Cloze cards ("A page fault occurs when ___")
- [ ] Search and move cards on the phone too
- [ ] Stats: reviews per day, retention per folder, streak
- [ ] Include or exclude folders from reminders; pause a folder

### Phase 4: Nice to have
- [ ] App icon (notifications currently show a placeholder)
- [ ] Home-screen widget showing the next due card
- [ ] Draft cards with an LLM from pasted notes, approved one by one
- [ ] Optimize FSRS weights from my own review history
- [ ] Host the sync server in the cloud and add a login, so syncing works away from home Wi-Fi
- [ ] Anki `.apkg` import

## Sync design notes

- **Two databases:** SwiftData on the phone and SQLite on the Mac. Every folder and card has a UUID shared across both.
- **Split ownership avoids most conflicts.** *Content* (folder name and parent, card front and back, card folder) is editable on both sides, and the newest `updatedAt` wins per record. *Progress* (FSRS state and review logs) is written only by the phone and copied to the Mac, so it never conflicts.
- **Protocol:** the phone sends `POST /sync { cursor, changes }`. The Mac applies the changes, then returns everything that changed after `cursor`, plus a new cursor. The cursor is a change sequence number on the Mac, so device clock skew only matters when the same card is edited on both sides between syncs.
- **Deletes** are tombstones (`deletedAt`), so a delete on one side removes the record on the other instead of the next sync bringing it back.
- **Moving to the cloud later** means the same server and protocol over HTTPS, plus a login. The phone code doesn't change beyond the server address.

## Notification design notes

- iOS keeps at most **64 pending local notifications** per app, and apps can't run code in the background on demand. So reminders are **planned ahead** (up to 7 days, within a 60-notification budget) and replanned whenever the app runs, including when a card is graded from a notification.
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

# Server tests, and the end-to-end sync test against a real server: see web/README.md

# Everything, including the UI tests (serial, since parallel clones start without notification permission)
xcodebuild test -project StudyUp.xcodeproj -scheme StudyUp \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO
```

Device testing: `TESTING.md` is the running checklist of what to verify on the iPhone. Add an item there for every new feature.

To run on the iPhone: open `StudyUp.xcodeproj`, pick the iPhone as the run destination, and press ⌘R. Repeat at least every 7 days, because of free provisioning.
