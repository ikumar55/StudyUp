# StudyUp — Device Testing Checklist

Things the simulator tests can't fully cover and that need checking on the iPhone. Tick an item when it works on the phone. Write anything odd in **Notes**, and say "check TESTING.md" in a session so it gets fixed.

Automated tests run on the simulator: `xcodebuild test … -parallel-testing-enabled NO` (see PLAN.md → Development). Before ticking anything here, install the latest build: open `StudyUp.xcodeproj`, choose the **StudyUp** scheme and your iPhone, then press ⌘R.

## Install and signing

| ✓ | Test | Notes |
|---|---|---|
| [ ] | App and notification extension install from Xcode without signing errors | |
| [ ] | After 7 days the app stops opening; pressing ⌘R again reinstalls it and **all cards are still there** | |

## Phase 1: Cards and studying

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Create a topic, a subfolder inside it, and a sub-subfolder | |
| [ ] | "Add and Start Next Card" saves the card, clears the form, and keeps the keyboard up for fast entry | |
| [ ] | Markdown shows correctly in the study view: **bold**, *italic*, `code` | |
| [ ] | Study a folder: Wrong brings the card back in about 1 minute, in the same session | |
| [ ] | Study a folder: Right on a new card brings it back in about 10 minutes, then in days | |
| [ ] | Folder badges and "Study now" counts look right after studying | |
| [ ] | Deleting a folder asks for confirmation and removes its cards | |
| [ ] | Settings (new cards per day, retention) are still set after quitting the app | |

## Phase 2: Reminders

| ✓ | Test | Notes |
|---|---|---|
| [ ] | The home screen offers "Turn On Study Reminders", and the iOS permission prompt appears | |
| [ ] | Home shows "Next reminder today at …" after allowing notifications | |
| [ ] | Settings → Send a Test Reminder arrives about 5 seconds later, **with the phone locked** | |
| [ ] | Tapping a reminder opens Quick Review starting with **that** card | |
| [ ] | Quick Review stops after "cards per reminder", and Keep Going continues | |
| [ ] | **Long-press** a reminder: the answer appears, and the buttons show intervals ("Right · 10m") | |
| [ ] | Grading from the long-press **without opening the app**, then opening the app, shows the card as reviewed | |
| [ ] | Grading from a notification while the phone is **locked** works (may ask for Face ID) | |
| [ ] | Tap a reminder while a card editor is open in a folder: the editor closes and Quick Review opens | |
| [ ] | Review a card in the app; any old notification for that card disappears from Notification Center | |
| [ ] | Real reminders arrive spread across the active hours (default 9 AM – 9 PM), not bunched together | |
| [ ] | No reminders arrive outside active hours | |
| [ ] | No reminders arrive when nothing is due | |
| [ ] | Reminders keep coming for several days **without opening the app** | |
| [ ] | Turning "Study reminders" off in Settings stops them | |

## Feel and feedback

Real use is what settles these defaults (currently up to 8 reminders a day, 3 cards each, 9 AM – 9 PM, 10 new cards a day).

| Question | Answer |
|---|---|
| Too many or too few reminders per day? | |
| Is 3 cards per reminder the right size? | |
| Are the notification sound and banner annoying, or fine? | |
| Anything slow or clunky when adding cards on the phone? | |

## Bugs found

| Date | What happened | Status |
|---|---|---|
| | | |
