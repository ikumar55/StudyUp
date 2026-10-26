# StudyUp

A personal spaced-repetition flashcard app built by and for one person, a new grad studying topics like OS fundamentals and ML foundations. Cards live in nested folders. The iPhone app sends a few cards at a time as notifications through the day, and spaced repetition (FSRS) decides what comes up when. A local web app on the Mac is for writing cards, and it syncs with the phone over Wi-Fi.

- **Read `PLAN.md` first.** It has the roadmap, the decisions made and why, design notes, and what's done (checkboxes).
- **`TESTING.md`** is the running checklist of things to verify on the real iPhone. Add rows for every user-visible feature.
- The user values **simplicity**: few numbers on screen, plain words ("later today", not "10m"), no extra buttons. They test on the simulator and their iPhone, then give UX feedback. Propose changes and confirm them before large redesigns.

## Repo layout

```
StudyUp/                     iPhone app (SwiftUI + SwiftData), iOS 26.5+
  Models/                    Folder, Card, ReviewLog, Tombstone; Persistence (container, backfill)
  Scheduling/                FSRS.swift (FSRS-5), StudyQueue (what's due), StudySession
  Reminders/                 ReminderPlanner (pure), ReminderScheduler (notifications), NotificationHandling (payload, delegate, grading)
  Sync/                      SyncProtocol (records), SyncMerger (merge rules), SyncEngine (HTTP, pairing, images), MacBrowser (Bonjour)
  Content/                   ImageStore (image files + ![](image:<id>) refs), Cloze
  Views/                     Home, Folder, CardEditor, StudySession, Settings, SyncSettings, TodaySchedule, CardContentView, Presenter, Components
  Settings/, Support/        UserDefaults keys and defaults; formatting (DueText), sample data
Shared/                      Compiled into BOTH the app and the notification extension: CardContent (block parser), RichText (Markdown + SwiftMath LaTeX), CodeHighlighter
StudyUpNotificationContent/  Notification Content Extension: long-press a reminder → question, answer, images; Wrong/Right/Easy buttons
StudyUpTests/                Swift Testing unit tests (+ SyncIntegrationTests against a live server)
StudyUpUITests/              XCTest UI tests (launch with -inMemoryStore)
Config/StudyUp-Info.plist    Extra Info.plist keys merged into the app's (Local Network, Bonjour, ATS local networking)
scripts/make-app-icon.swift  Draws the app icon (light/dark/tinted PNGs) into Assets.xcassets/AppIcon.appiconset
web/                         Mac web app (see web/README.md)
  shared/                    protocol.ts (sync records, mirrored in Swift), images.ts (image reference syntax)
  server/                    Node 26 + TypeScript run directly (no build), Hono, node:sqlite; store.ts holds the merge rules
  client/                    React + Vite editor (react-markdown, KaTeX, highlight.js)
  scripts/                   install-service.sh / uninstall-service.sh (launchd login service)
```

## How it fits together

- **Scheduling.**
  - New cards per day is a maximum: only as many start as today's remaining reminders can carry after what's due (`StudyQueue.newCardsForToday`). Use that, not `remainingNewCards`, anywhere that decides what to study.
  - FSRS-5, with learning steps sized for studying in reminders rather than sessions (`FSRS.defaultLearningSteps`): Wrong → 15 min, which lands in the **next reminder**; Right on a learning card → **3 hours**, a same-day check; Right again → graduates to days. Relearning after a lapse is 15 min.
  - Sessions show each card once (no in-session repeats). "Ready now" counts only cards that are actually due.
  - There are three grades: Wrong/Right/Easy, which are FSRS Again/Good/Easy.
  - Scheduling fields are stored flat on `Card` so predicates can use them. `CardSchedule` + `FSRS` are pure and unit-tested.
  - Answer labels come from `DueText` and are plain words ("next reminder", "in a few hours", "in 4 days"). The user cares a lot about these being clear.
- **Reminders.**
  - iOS can't wake the app on demand, so `ReminderScheduler` plans up to 7 days of notifications ahead, within a 60-notification budget, and replans whenever the app opens or goes to the background, after sessions and settings changes, when the card count changes, and after a grade from a notification.
  - Each reminder carries its exact cards (`cardIDs` = sync ids). Tapping one opens a Quick Review of those cards.
  - `upcomingToday` / `sentToday` drive the home "Today" summary and the Today screen.
- **Sync.**
  - Two databases: SwiftData on the phone, SQLite on the Mac at `~/Library/Application Support/StudyUp/`. They share UUIDs (`syncID`).
  - The phone always initiates with `POST /sync {cursor, changes}`; the Mac merges and returns what changed after the cursor.
  - Content: newest `updatedAt` wins per record. Progress: newest `progress.updatedAt` wins. It's normally written only by the phone; the web app's Review today and Reset progress also write it.
  - Deletes travel as tombstones; the Mac keeps a deleted record's text. Review logs are append-only and come back on a cursor-0 sync, which restores a reinstalled app.
  - Edit times more than a day ahead of the Mac's clock are capped (`validate.ts`).
  - Each response carries a `databaseId`. If it changes (the Mac's database was replaced), the phone does a full sync: cursor 0, everything sent, review logs marked unsent.
  - The server keeps daily snapshots in `backups/` next to the database (14 kept), checkpoints the WAL after each sync, and closes the database on SIGTERM.
  - Pairing uses a 6-digit code shown in the editor, which gets a token stored in the iOS Keychain.
  - The editor API is localhost-only: the connection must come from this Mac, the `Host` must be localhost, changes need a localhost `Origin` (or none), and bodies must be JSON. Other devices can only reach `/pair`, `/sync` and `/images/*`, and only with the token. Request sizes are capped per route.
- **Images.**
  - Card text refers to images as `![](image:<uuid>)`.
  - Files are stored next to each database and synced after cards: the phone uploads the images its cards use that the Mac lacks, then downloads the ones it lacks.
  - The web scales images to 2000 px WebP; the phone uses 2000 px JPEG.
  - Images no card uses are removed after 7 days on both sides.
  - Notifications get JPEG copies as attachments, since the extension can't read the app's container (no App Groups on the free account).
- **Rich content:** Markdown, fenced code (with colors when a language is named), `$inline$` / `$$display$$` LaTeX, and images. Cloze `{{blank}}`, `{{c1::group}}` and `{{answer::hint}}` expand into one card per blank when created, on both clients.

## Rules that are easy to break

- **Keep mirrored code in sync:**
  - `web/shared/protocol.ts` ↔ `StudyUp/Sync/SyncProtocol.swift`
  - `web/client/src/cloze.ts` ↔ `StudyUp/Content/Cloze.swift`
  - `dueText` (web `format.ts`) ↔ `DueText` (`Formatting.swift`)
  - The notification payload keys in `NotificationHandling.swift` ↔ `NotificationViewController.swift`
  - The image reference regex, in several places
- **SwiftData migrations:** new stored properties must be optional (or have a constant default that's safe for every row). A default like `UUID()` is evaluated once in migration, so every existing row would get the same value. Fill real values in `Persistence.backfillSyncMetadata`.
- **Use the sync-aware helpers:**
  - `context.deleteSyncing(_:)`, never `context.delete`, for folders and cards; it records tombstones
  - `Card.edit` / `Folder.rename` for content changes, which bump `updatedAt`
  - `Card.record` for grading
  - `reviewToday()` / `resetProgress()` for progress changes
- **Present every sheet and session through `Presenter`** (environment object from `HomeView`). iOS shows one modal at a time, and reminder taps rely on this.
- **Concurrency:**
  - The app target uses default MainActor isolation; the extension and test targets don't. Code in `Shared/` must compile under both, so mark pure types `nonisolated`.
  - Swift requires explicit imports (MemberImportVisibility), so add `import SwiftData` etc. to any file that uses them.
- **Notifications:**
  - The `UNUserNotificationCenterDelegate` methods use the completion-handler variants. The async ones crashed when completing off the main thread.
  - Replans remove only pending requests prefixed `reminder-`, so a test reminder survives.
- **Web:**
  - Node runs `.ts` directly, so imports need `.ts` extensions, and only erasable syntax is allowed (no enums or parameter properties).
  - `package.json` overrides `katex` to the patched version.

## Commands

```bash
# iPhone: build / all tests (UI tests must run serially)
xcodebuild build -project StudyUp.xcodeproj -scheme StudyUp -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -project StudyUp.xcodeproj -scheme StudyUp -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO

# Live sync test: start a throwaway server, then point the tests at it
(cd web && STUDYUP_DB=/tmp/studyup-test.db PORT=8799 node server/index.ts &)
TEST_RUNNER_STUDYUP_SERVER=http://localhost:8799 xcodebuild test … -only-testing:StudyUpTests/SyncIntegrationTests

# Web (run in web/)
npm test            # server + client tests (node --test)
npm run typecheck
npm run build       # editor → client/dist
npm run dev:server  # API on :8787;  npm run dev:client → editor on :5173
./scripts/install-service.sh   # the user's real server: copies the app to Application Support and (re)starts the launchd service
```

- Never use port 8787 or the default database for tests. Use `STUDYUP_DB` and `PORT` with a throwaway path.
- After changing anything under `web/`, re-run `install-service.sh`. Otherwise the user's running copy stays old.
- UI tests share the simulator's UserDefaults with manual use. For example, the user set 1 card per reminder, so don't assume default settings in assertions.
- To check UI changes, look at screenshots: XCTest attachments exported with `xcrun xcresulttool export attachments`, and headless Chrome over the DevTools protocol for the web.

## Working with the user

- **Commit only when asked, and push only when asked**; they often say "commit but don't push".
  - Commit messages: a short imperative title, a bullet body, and the co-author trailer.
  - Git identity is set repo-locally to `ikumar55` (noreply email), and pushes authenticate as `ikumar55` via the keychain. The machine's default GitHub login is a different account, so don't change this config.
- **Free Apple developer account:** the app expires after 7 days and is reinstalled with ⌘R. There's no CloudKit or App Groups.
- **Before saying something is done,** build and run the relevant tests, update `PLAN.md` checkboxes, and add `TESTING.md` rows.
