# StudyUp — Project Plan

## Goal

A personal iOS app for **micro-studying through the day**. I write flashcards as I learn (OS fundamentals, ML foundations, and more), organize them in nested folders, and the app sends short review prompts throughout the day. Spaced repetition decides what comes up and when, so I keep what I've learned without long study sessions.

**The one feature that matters most:** a notification arrives, I answer one to three cards in under a minute, and I'm done. Everything else supports that loop.

## Principles

- **Low friction beats features.** Reviewing from a notification and adding a card should each take seconds.
- **Retention is the metric.** Scheduling follows the research (FSRS); don't invent intervals.
- **One fact per card.** The app should nudge toward small, single-fact cards, which are easy to grade honestly.
- **Local first.** All data stays on my own devices (the iPhone and my Mac), with no cloud and no account.

## Decisions made

| Decision | Choice | Why |
|---|---|---|
| Platform | Native iOS, SwiftUI, iOS 26.5+ | First-class notification APIs; matches the iPhone (26.5.2) |
| Storage | SwiftData, on device | Built in; models are in `StudyUp/Models/Models.swift` |
| Scheduler | FSRS-5 with learning steps of 15 min and 3 h (relearn 15 min) | FSRS is Anki's current default. The steps were changed on 2026-10-26 from Anki's 1m/10m to suit studying in short reminders: Wrong → next reminder, Right → a same-day check. Day-scale intervals get Anki's fuzz (2026-10-26) |
| Grading | Wrong / Right / Easy (FSRS Again / Good / Easy) | Chosen 2026-10-19; "Hard" adds little |
| Apple account | Free (Personal Team) | No $99/yr. The app must be reinstalled from Xcode every 7 days. No iCloud/CloudKit, and App Groups may not be available |
| Writing cards on the Mac | Local web app on the Mac (TypeScript: React UI + Node server + SQLite) that syncs with the phone over Wi-Fi (phase 3) | Chosen 2026-10-20 over a phone-hosted editor: you can write anytime, the Mac keeps a backup, and it can move to the cloud later by hosting the same server |
| Bundle ID | `com.ikumar55.StudyUp` | |
| Git identity | Repo-local config pushes as `ikumar55` | The machine's default GitHub login is a different account |

## Architecture

See **CLAUDE.md** for the repo layout, how the pieces fit together, the rules that are easy to break, and the commands. It's kept current; this file is the roadmap.

## Next up (as of 2026-10-26)

1. **Test on the iPhone** using TESTING.md. Most features have only been checked on the simulator and the Mac.
2. **Restore from a backup.** The Mac now keeps daily snapshots (`backups/`) and the JSON download, but neither can be restored from the editor yet. A restore must give the database a new `databaseId`, so the phone sends everything it has. A reinstalled app already gets everything back from the Mac on its first sync, so this matters most if the Mac's database is lost.
3. **Tune defaults from real use:** reminders per day, cards per reminder, new cards per day, and the 3-hour check.
4. Then: **Pause and Focus folders** (design under To consider → iPhone app), search and move on the phone, stats (Phase 3.5 leftovers below), the ideas in **To consider**, and Phase 4.

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
- [x] Notification Content Extension (`StudyUpNotificationContent/`): long-press shows the answer; buttons say when the card comes back ("Right · in 4 days")
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
- [x] ⌘B bolds the selected text in any card field, and unbolds it if it's already bold (2026-10-26)
- Bulk paste (`Q:`/`A:` blocks, `question :: answer` lines, tab-separated) was built, then removed on 2026-10-26: rarely needed, and cards are better written one at a time
- [x] Search across all cards (⌘K); move cards between folders
- [x] Download a backup (JSON); iPhone pairing panel; live updates when the phone syncs (polls every 3 s)

### Phase 3.5: Rich content ✅ (2026-10-20, built and tested on simulator and Mac; device testing pending)
- [x] **Images** (2026-10-20). Cards refer to images as `![](image:<id>)`, the same in the app and on the web. Files are stored next to each database and synced separately: the phone uploads what the Mac lacks, then downloads what it lacks.
  - Web: paste (⌘V), drop, or "Image…"; large images are scaled to 2000 px and stored as WebP; click to zoom
  - iPhone: "Add Image" from Photos in the card editor (scaled to 2000 px, JPEG); tap to zoom full screen, pinch or double-tap to zoom in
  - Notifications: 📷 in the banner text; question images appear as the banner thumbnail; answer images are hidden until long-press
- [x] **Code blocks** on the iPhone (the web already had them): a monospaced box that scrolls sideways
- [x] **LaTeX** (2026-10-20): `$inline$` and `$$display$$`. KaTeX on the web; SwiftMath 1.7.x (Swift package) on the iPhone and in the notification view. Bad LaTeX shows in red without breaking the card.
- [x] **Syntax colors** in code blocks that name a language (```c): highlight.js on the web; a small built-in highlighter on the iPhone (`Shared/CodeHighlighter.swift`)
- [x] **Cloze cards**: `{{blank}}`, `{{c1::grouped}}`, `{{answer::hint}}`, one card per blank (or group), same rules on web (`cloze.ts`) and iPhone (`Cloze.swift`)
- [x] Unused image files are removed after 7 days, on the Mac and the iPhone; the phone only uploads images its cards use
- [x] The backup download includes images (as base64)
- [ ] Restore from a backup file (the backup can be downloaded, but not restored yet)
- Shared code: `Shared/` is compiled into both the app and the notification extension (card parser, math, code colors)
- [ ] Search and move cards on the phone too
- [ ] Stats: reviews per day, retention per folder, streak
- [ ] Include or exclude folders from notifications; pause a folder → designed as **Pause and Focus** (To consider → iPhone app)

### Phase 3.6: Feedback from the first simulator run (2026-10-21)
- [x] Removed "Add and Start Next Card"; Add saves and closes
- [x] Plain-language intervals: "again today", "later today", "tomorrow", "in 4 days" (study buttons, notification buttons, card status, web badges)
- [x] Home shows **Today: N cards left**, with reminders left and the next one's time and size, instead of a bare "3 due"
- [x] **Today** schedule screen (today only): upcoming reminders with their cards, "Study These Now", and those already sent
- [x] Each reminder carries its exact cards, so tapping it reviews what the schedule showed
- [x] **Review Today** and **Reset Progress** for a card, on the iPhone (card editor) and the web (card "…" menu); the web's change reaches the phone on its next sync

### Phase 3.7: Scheduling for studying through the day (2026-10-26)
- [x] Learning steps changed from Anki's 1 min / 10 min (made for long sessions) to **15 min / 3 hours**:
  - Wrong → the **next reminder** (15 min means it never comes back in the same sitting)
  - Right on a card still being learned → **a same-day check in about 3 hours**
  - Right again → graduates to days (4 → 14 → 44 days …); Easy skips straight to days (16 days)
  - A forgotten review card → next reminder, then back to days
- [x] Study sessions show each card once (no in-session repeats), and "ready now" only counts cards that are actually due
- [x] Answer labels: Wrong · "next reminder", Right while learning · "in a few hours" ("tomorrow" if after reminder hours), otherwise days
- Load note: each new card shows at least twice on its first day. "New cards per day" is the main dial if days feel crowded.

### Phase 3.8: Reminder fixes from the code review (2026-10-26)
- [x] **"Up to N a day" is now a real limit.** Every replan (after each answer, app open, or app close) used to treat the rest of the day as a fresh day, so 8 a day became 16–19, bunched in the evening. Reminders now sit on fixed times, and the ones already sent count toward the limit. Planned reminders are kept for every day, so ones that go off while the app is closed still count.
- [x] **Reminder times stay put** when the app replans (opening it no longer pushes the next reminder later)
- [x] **Daylight saving:** active hours use clock times, so on the days the clocks change reminders still run 9–9, not 8–8 or 10–10
- [x] **No interruptions while studying:** during a session, reminders go quietly to Notification Center instead of showing a banner, and the plan updates a few seconds after each grade
- [x] **No lost work in the card editor:** swiping down can't discard a draft; Cancel asks first; a reminder tapped mid-draft waits until the card is done instead of closing the editor
- [x] **Deleting a card asks first** (swipe or Delete Card), like folders
- [x] **On going to the background, reminders are replanned before syncing,** so a slow or unreachable Mac can't stop the replan; if iOS runs out of time, the sync is cancelled cleanly

### Phase 3.9: Mac data safety, security, and new cards that fit (2026-10-26)
- [x] **Daily backups:** the server saves a complete snapshot of the database once a day to `~/Library/Application Support/StudyUp/backups/` (keeps 14). It also folds the write-ahead log into `studyup.db` after each sync and closes the database on shutdown, so the `.db` file alone is always complete
- [x] **Deletes from the phone keep the card's text on the Mac** (only marked deleted), so a mistaken delete can be recovered later
- [x] **Edit times more than a day ahead of the Mac's clock are capped**, so a wrong clock or forged request can't win every later edit
- [x] **Editor API hardened:** requests must be addressed to localhost and, for changes, come from a localhost page (blocks DNS rebinding and cross-site posts); bodies must be JSON; request sizes are capped (16 KB for `/pair`, 15 MB for images, 64 MB for `/sync`, 1 MB otherwise)
- [x] **Replaced Mac database → full sync:** `/sync` returns a `databaseId`. The Mac changes it when a phone's cursor is ahead of the database (an older copy was put back); the phone then sends everything, including review history, and receives everything
- [x] **An edit that loses on the Mac goes back to the phone,** even if the phone had seen the Mac's version before (a phone clock running behind). Before, the phone kept its losing text for good. A phone delete that loses to a newer Mac edit brings the card back
- [x] **New cards fit in the reminders:** today's new cards are the daily setting, but only as many as today's remaining reminders can carry after what's already due (two places each, for the same-day check). Home, the Today screen, Study now, Keep Going and the reminder plan all use this number; the rest wait for a day with room. With reminders off, just the setting

### Phase 3.10: Interval fuzz (2026-10-26)
- [x] Intervals of 3 days or more move a little earlier or later, by Anki's ranges (4 days → 3–5, 14 → 12–16, Easy's 16 → 13–19, 44 → 40–48), so cards learned together don't keep coming due on the same days. Learning steps and 1–2 day intervals are unchanged; so are the FSRS-5 formulas and weights
- [x] The nudge comes from the card's sync id and review count (not the time), so the label on a button or notification always matches what grading does

### Phase 3.11: "Notifications" wording (2026-10-26)
- [x] On screen, "reminder" is now "notification" everywhere (Settings, Home, Today, the card editor, the Wrong button's "next notification"); the code keeps its names
- [x] Home's second line reads on from the first: "Today: 3 cards left / Over 2 notifications · next at 5:15 PM" ("Next notification at …" when one is left)
- [x] When a notification arrives while the app is open, the app replans right away, so Home shows the next time and Today moves the delivered one to "Earlier today" (they used to stay stale until the app replanned for another reason). Times that have passed are never shown as upcoming

### Phase 4: Nice to have
- [x] App icon (2026-10-26): two stacked cards with a rising line, matching the web editor's favicon; light, dark and tinted versions. Drawn by `scripts/make-app-icon.swift`
- [ ] Home-screen widget showing the next due card
- [ ] Draft cards with an LLM from pasted notes, approved one by one
- [ ] Optimize FSRS weights from my own review history
- [ ] Host the sync server in the cloud and add a login, so syncing works away from home Wi-Fi
- [ ] Anki `.apkg` import

## To consider

Ideas from the 2026-10-26 research (code review of both apps, plus spaced-repetition research and other apps). Not committed to; pick from here. Sizes: S small, M medium, L large.

**Scheduling**
- **Upgrade to FSRS-6, together with optimizing weights** (S + M). Two more weights: a trainable forgetting curve, and same-day reviews that help less once a card is well known. Its benchmark gains (log loss 0.46 → 0.38 with same-day reviews) come mostly from weights fitted to your own history; with default weights it mostly changes the day-gaps (4 → 14 → 44, Easy's 16) rather than clearly improving them. So do it with the optimizer below, after a few hundred reviews. Decided 2026-10-26 to keep FSRS-5 until then. The official [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) can check our numbers. FSRS-7 (two memory traces, built for same-day reviews) exists but isn't in a stable release yet.
- **Load balancing** (S–M). Fuzz (Phase 3.10) already spreads cards across nearby days; load balancing would pick the least busy day within the fuzz range, as Anki does since 24.11. It needs every card's due date when computing button labels (in sessions and when planning notifications), so it's more code. Worth it if some days feel crowded.
- **Keep Going past today's new cards** (S). Now that new cards are limited to what fits in reminders (Phase 3.9), a session's Keep Going could offer a few extra new cards on days you want to study more. Their same-day checks would then compete for reminder slots.
- **Keep cloze siblings apart** (M). Cards from one cloze sentence give away each other's answers, and today they arrive in back-to-back reminders. Needs an optional `noteID` on cards (mirrored in `protocol.ts`), then at most one sibling per day.
- **Cards that keep failing** (S). After ~6–8 lapses, stop putting the card in reminders and list it as "Cards to rewrite" in the web editor. `lapses` already syncs.
- **Optimize FSRS weights on the Mac** (M; Phase 4 item). The Mac already has every review log. `@open-spaced-repetition/binding` runs the official optimizer in Node; send the weights to the phone as a synced record. Re-run when the review count doubles; no button.

**Reminders**
- **Mix topics within a reminder** (S). When several cards are equally due, pick from different folders; interleaving helps tell related ideas apart.
- **Ease off when reminders are ignored** (S–M). If the last few got no answer and no app open, space the next ones further apart; back to normal after any answer. No guilt messages.
- **"Show Answer" button on the notification** (S–M). Sends the answer as a follow-up notification with the grade buttons, so it works on an Apple Watch and without a long-press.
- **Reminder hours past midnight, and a 4 AM day boundary** (M). "Until 1:00 AM" currently turns reminders off entirely, and a 00:30 session counts toward the next day.
- **Home says why there are no reminders** (S). With notifications denied in iOS Settings, Home says "Notifications are off" although the toggle is on.

**iPhone app**
- **Pause and Focus folders** (M; designed and agreed 2026-10-26). Two options in a folder's ⋯ menu on the phone:
  - **Pause:** the folder's cards (subfolders included) stop coming up: not in notifications, Home's Study now, or the "cards left" counts. The folder row shows "Paused"; **Resume** brings it back. A paused folder starts no new cards.
  - **Focus on This Folder:** the opposite: only this folder's cards come up (notifications, Study now, counts, new cards) until you stop. Home shows one line, "Focusing on OS Fundamentals · Stop", so it isn't forgotten. One focus at a time.
  - A folder's own Study now keeps working either way (a paused folder can still be studied on purpose).
  - Both go through the one place that decides which cards count (`StudyQueue` candidates), so notifications, Study now, counts and the new-cards-that-fit limit all agree.
  - Schedules don't change while paused or out of focus. Cards that fell due meanwhile come back together on resume; FSRS handles the extra elapsed time correctly. Fine for days of exam prep; a long focus means a catch-up after.
  - Stored on the phone only at first (a set of folder sync ids in UserDefaults; focus as one id), so no protocol change. Showing or changing them in the web editor would mean a synced folder field, mirrored in `protocol.ts` / `SyncProtocol.swift`.
  - TESTING.md rows to add when built: pausing removes the folder's cards from notifications and counts; resume brings them back; focus limits notifications to one folder; the Home focus line stops it.
- **New Card from Home** (S–M). Adding a card takes Home → topic → folder → + → New Card. A Home button (last-used folder, with a folder picker in the editor) plus a long-press app-icon shortcut.
- **Undo the last grade** (S–M). A mis-tapped Wrong can't be taken back.
- **Accessibility** (S). The three grade buttons truncate at large text sizes (stack them); inline math has no VoiceOver label.
- **Performance with thousands of cards** (M). Home and folder views rebuild study queues for every topic on each render; full-size images are decoded on the main thread.
- **Try App Groups on the free account** (10-minute test). Apple's capability table lists App Groups as available to free accounts, contrary to our assumption. If they work: a home-screen widget, and the notification extension could read images directly.
- Interactive widget, App Shortcuts ("Study now"), a lock-screen Live Activity: possible later; Live Activity buttons don't work while the phone is locked.

**Web editor**
- **Due forecast** (S): cards due on each of the next 7 days, as of the last phone sync. Helps tune new cards per day.
- **"Often missed" filter** (S): cards with many lapses, to rewrite or split.
- **Multi-select** (M): ⇧/⌘-click several cards to move or delete them.
- **Duplicate warning** (S): a hint when a new question matches an existing one.
- **Confirm before discarding an inline edit** (S); Esc currently drops changes silently.
- **"Recently deleted"** (M): possible now that deletes from the phone keep their text on the Mac.

**Known issues** (smaller, from the same review)
- A card added or edited on the phone inside a folder deleted on the Mac (before the next sync) is lost on the phone.
- An open study session or card editor can hold a card that a sync just deleted; a card graded from a notification while shown in a session gets graded twice.
- A crash-corrupted database leaves the server restarting every 10 s with no clear message.
- Editor: a quick-add draft holding a pasted image, saved more than 7 days later, has a broken image; leftover `*.partial` image files are never cleaned up.
- `npm start` / `npm run dev:server` default to the real database and port 8787.

Considered and skipped: streaks (pressure), typing the answer (too slow on a lock screen), reverse cards, per-folder retention targets (more numbers).

## Sync design notes

- **Two databases:** SwiftData on the phone and SQLite on the Mac. Every folder and card has a UUID shared across both.
- **Split ownership avoids most conflicts.** *Content* (folder name and parent, card front and back, card folder) is editable on both sides, and the newest `updatedAt` wins per record. *Progress* (FSRS state and review logs) is written only by the phone and copied to the Mac, so it never conflicts.
- Exception: the web app's Review today and Reset progress also write progress. That's safe because the newest `progress.updatedAt` wins on both sides.
- **Protocol:** the phone sends `POST /sync { cursor, changes }`. The Mac applies the changes, then returns everything that changed after `cursor`, plus a new cursor. The cursor is a change sequence number on the Mac, so device clock skew only matters when the same card is edited on both sides between syncs.
- **Deletes** are tombstones (`deletedAt`), so a delete on one side removes the record on the other instead of the next sync bringing it back. The Mac keeps a deleted record's text and only marks it deleted.
- **Edit times** more than a day ahead of the Mac's clock are capped, since newest wins.
- **Database id:** each `/sync` response names the Mac's database. If it changes (the Mac changes it when a phone's cursor is ahead of its own; a restore should too), the phone starts over: cursor 0, everything sent, review history marked unsent.
- **Moving to the cloud later** means the same server and protocol over HTTPS, plus a login. The phone code doesn't change beyond the server address.

## Notification design notes

- iOS keeps at most **64 pending local notifications** per app, and apps can't run code in the background on demand. So reminders are **planned ahead** (up to 7 days, within a 60-notification budget) and replanned whenever the app runs, including when a card is graded from a notification.
- Each day has fixed reminder times: "up to N a day" slots, each in the middle of its share of the active hours (9–21 with 8 a day: 9:45, 11:15, … 20:15). A plan uses only as many as the due cards need (due cards ÷ cards per reminder), spread over the slots still ahead, and reminders already sent today count toward N. So replanning never moves a reminder or adds extra ones.
- A card that isn't ready at its slot (e.g. a 3-hour check) goes in the first slot after it's ready.
- Active hours are clock times on each day (not minutes after midnight), so they hold when the clocks change.
- During a study session in the app, reminders arrive quietly (Notification Center only).
- Each reminder carries its exact cards (sync IDs), and the first one is shown in the banner. Tapping it reviews those cards, the same ones the Today screen listed.
- Cards marked Wrong come back after 15 minutes, which lands in the next reminder. A session never shows a card twice.

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
