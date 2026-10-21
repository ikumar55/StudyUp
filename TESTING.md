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

## Phase 3: Mac web app and sync

Set up first: run `web/scripts/install-service.sh` on the Mac, then open http://localhost:8787.

| ✓ | Test | Notes |
|---|---|---|
| [ ] | The editor opens at localhost:8787 and still works after restarting the Mac (the service starts at login) | |
| [ ] | iPhone: Settings → Sync with Mac asks for **Local Network** permission, then lists the Mac | |
| [ ] | Pairing with the 6-digit code from the editor works; a wrong code shows an error | |
| [ ] | Cards already on the phone appear in the editor after the first sync | |
| [ ] | A card written in the editor appears on the phone after reopening the app | |
| [ ] | A card edited on the phone shows the edit in the editor | |
| [ ] | Deleting a folder on either side removes it on the other after a sync | |
| [ ] | Studying on the phone updates the card status in the editor ("Due in 3d") | |
| [ ] | Grading from a notification, then opening the app, syncs that review | |
| [ ] | With the Mac asleep or on other Wi-Fi, the phone shows "Couldn't reach your Mac" and nothing breaks | |
| [ ] | Bulk paste in the editor creates many cards, which reach the phone | |
| [ ] | Delete and reinstall the app, pair again: all cards **and their progress** come back | |
| [ ] | Another computer on the Wi-Fi can't open the editor (try http://<mac-name>.local:8787 from another device: expect "only available on the Mac running it") | |

## Phase 3.5: Images and code

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Web: take a screenshot (⌘⇧⌃4 copies it), click into Answer, ⌘V: the image appears in the card after adding | |
| [ ] | Web: drag an image file onto a field; "Image…" picks a file | |
| [ ] | Web: click an image in a card to see it full size; Esc closes | |
| [ ] | The image reaches the phone after a sync, and shows in the study view | |
| [ ] | iPhone: Edit Card → Add Image picks from Photos; the thumbnail shows, and × removes it | |
| [ ] | An image added on the phone shows in the web app after a sync | |
| [ ] | iPhone: tap an image while studying: full screen; pinch and double-tap zoom work | |
| [ ] | A card whose answer is only an image can be saved | |
| [ ] | Reminder for a card with a question image: thumbnail in the banner; answer images only on long-press | |
| [ ] | A card with a ```code block``` shows a monospaced box on the phone, not backticks | |
| [ ] | Editing a card on the phone that has an image in the middle of its text (written on the Mac) doesn't move the image unless that field is changed | |
| [ ] | Math: `$\\frac{1}{\\sqrt{d_k}}$` inline and a `$$…$$` line render properly in the web app, the study view, and the long-press notification | |
| [ ] | Math in Dark Mode on the phone is white, not black | |
| [ ] | Cloze: "A {{page fault}} occurs when a page isn't in {{physical memory}}." makes 2 cards, on both the web and the phone | |
| [ ] | Bulk paste of cloze sentences (one per line) makes one card per blank | |
| [ ] | A code block starting with ```c (or python, js, swift…) shows syntax colors on both sides | |
| [ ] | Download backup: the file includes an "images" section | |

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
