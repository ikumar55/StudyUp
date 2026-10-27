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
| [ ] | Markdown shows correctly in the study view: **bold**, *italic*, `code` | |
| [ ] | Study a folder: Wrong doesn't repeat the card in that session; it's due again in the next reminder | |
| [ ] | Study a folder: Right on a new card brings it back in about 3 hours, then in days | |
| [ ] | Folder badges and "Study now" counts look right after studying | |
| [ ] | Deleting a folder asks for confirmation and removes its cards | |
| [ ] | Deleting a card (swipe left in a folder, or Delete Card in the editor) asks first | |
| [ ] | Settings (new cards per day, retention) are still set after quitting the app | |

## Phase 2: Reminders

| ✓ | Test | Notes |
|---|---|---|
| [ ] | The home screen offers "Turn On Study Notifications", and the iOS permission prompt appears | |
| [ ] | Home shows "Next reminder today at …" after allowing notifications | |
| [ ] | Settings → Send a Test Notification arrives about 5 seconds later, **with the phone locked** | |
| [ ] | Tapping a reminder opens Quick Review starting with **that** card | |
| [ ] | Quick Review stops after "cards per notification", and Keep Going continues | |
| [ ] | **Long-press** a reminder: the answer appears, and the buttons say when the card comes back ("Right · in a few hours") | |
| [ ] | Grading from the long-press **without opening the app**, then opening the app, shows the card as reviewed | |
| [ ] | Grading from a notification while the phone is **locked** works (may ask for Face ID) | |
| [ ] | Tap a reminder while a card editor is open **with nothing typed**: the editor closes and Quick Review opens | |
| [ ] | Tap a reminder while **writing** a card: the editor stays, with a note that the notification's cards open when you're done; after Add (or Cancel → Discard), Quick Review opens | |
| [ ] | Review a card in the app; any old notification for that card disappears from Notification Center | |
| [ ] | Real reminders arrive spread across the active hours (default 9 AM – 9 PM), not bunched together | |
| [ ] | No reminders arrive outside active hours | |
| [ ] | No reminders arrive when nothing is due | |
| [ ] | Reminders keep coming for several days **without opening the app** | |
| [ ] | Turning "Study notifications" off in Settings stops them | |

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
| [ ] | Delete and reinstall the app, pair again: all cards **and their progress** come back | |
| [ ] | Another computer on the Wi-Fi can't open the editor (try http://<mac-name>.local:8787 from another device: expect "only available on the Mac running it") | |

## Phase 3.5: Images and code

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Web: take a screenshot (⌘⇧⌃4 copies it), click into Answer, ⌘V: the image appears in the card after adding | |
| [ ] | Web: drag an image file onto a field; "Image…" picks a file | |
| [ ] | Web: click an image in a card to see it full size; Esc closes | |
| [ ] | Web: select a word in Question or Answer (or while editing a card) and press ⌘B: it turns bold; ⌘B again undoes it | |
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
| [ ] | A code block starting with ```c (or python, js, swift…) shows syntax colors on both sides | |
| [ ] | Download backup: the file includes an "images" section | |

## Phase 3.6: Today view and card progress

| ✓ | Test | Notes |
|---|---|---|
| [ ] | The card editor no longer has "Add and Start Next Card"; Add saves and closes | |
| [ ] | Study buttons say: Wrong · "next notification", Right on a new card · "in a few hours", Right on a learned card · "in N days" | |
| [ ] | Long-press notification buttons use the same wording | |
| [ ] | Home: "Today: N cards left" goes down as you answer, and back up when you get one wrong | |
| [ ] | Home → Today lists upcoming reminders with their cards; earlier ones show as sent | |
| [ ] | Tapping a reminder reviews exactly the cards the Today screen listed for it | |
| [ ] | Today → a reminder → Study These Now works | |
| [ ] | Card editor: Review Today makes the card due now; Reset Progress (with confirmation) makes it New | |
| [ ] | Web: card "…" → Review today / Reset progress…, and the phone shows the change after a sync | |

## Phase 3.7: Studying through the day

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Answering Wrong in a Quick Review doesn't show that card again in the same review | |
| [ ] | A card you got Wrong shows up in the **next** reminder (Today screen lists it there) | |
| [ ] | A new card answered Right comes back in a reminder about 3 hours later, then goes to days after another Right | |
| [ ] | Right late in the evening (within 3 hours of your reminder end time) says "tomorrow" and arrives in the first reminder next morning | |
| [ ] | Study now right after a Wrong doesn't immediately show that card again | |

## Phase 3.8: Reminder fixes

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Over a whole day, the reminders that arrive never go past "Up to N a day", even when you answer each one right away (count them in Home → Today → Earlier today) | |
| [ ] | Reminders arrive at the same times every day (at 9–9 with 8 a day: 9:45, 11:15, 12:45 …), and opening the app doesn't move the next one | |
| [ ] | **Sun Nov 1 (clocks go back):** the first reminder comes at 9:45, not 8:45; Settings still shows From 9:00 | |
| [ ] | During a study session, a reminder doesn't pop up over it; it's waiting quietly in Notification Center | |
| [ ] | Writing a new card: swiping the sheet down doesn't close it; Cancel asks "Discard this card?" | |
| [ ] | Editing a card without changing anything: Cancel and swipe-down close it right away | |
| [ ] | With the Mac asleep, study a few cards and lock the phone: the next reminder doesn't show a card you just answered | |

## Phase 3.9: Mac safety and new cards that fit

| ✓ | Test | Notes |
|---|---|---|
| [ ] | After the Mac has been on for a day or two, `~/Library/Application Support/StudyUp/backups/` has one `studyup-<date>.db` per day | |
| [ ] | The editor still works in Safari and Chrome: add, edit, move and delete cards and topics | |
| [ ] | Home's "Today: N cards left" fits what today's reminders cover (Today screen); with 1 card a reminder and 8 reminders, at most 4 new cards start a day (fewer when reviews are due) | |
| [ ] | Study now offers the same new cards the reminders would, not the full "new cards per day" | |
| [ ] | After your last reminder of the day, Study now offers no new cards; they come tomorrow | |
| [ ] | Raising cards per reminder (Settings) makes room for more new cards today | |
| [ ] | Delete a card on the phone and sync: it disappears from the editor | |

## Phase 3.10: Interval fuzz

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Cards learned on the same day don't all come back on the same day: their next reviews spread over a few days (e.g. 3–5 days later instead of all at 4) | |
| [ ] | When a button or notification says "in 5 days", the card really comes back 5 days later (check its status in the card editor) | |

## Phase 3.11: "Notifications" wording

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Home under "Today: N cards left" reads "Over 2 notifications · next at 5:15 PM" (or "Next notification at …" when one is left) | |
| [ ] | The app says "notification" everywhere: Settings section and toggle, "cards per notification", Send a Test Notification, the Wrong button's "next notification", the Today screen | |
| [ ] | With the app open on Home or Today when a notification arrives: Home moves on to the next time, and Today moves it to "Earlier today" | |

## Phase 3.12: The end of the day follows the last notification

With the default hours (9 AM – 9 PM, up to 8 a day) the last notification is at 8:15 PM.

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Answer a card Wrong after 8:15 PM, then go Home: the top row says "All done for today · next tomorrow at 9:45", not "1 card left" | |
| [ ] | Home's "Today: N cards left" matches the cards listed under Coming up on the Today screen | |
| [ ] | Around 6 PM, the Right button on a card still being learned says "tomorrow" (its check would come after 8:15 PM); before 5 PM it says "in a few hours" | |
| [ ] | The long-pressed evening notification's Right button says the same as the app would | |
| [ ] | That card's status (in its folder list and the card editor) also says "Due tomorrow", not "Due later today" | |
| [ ] | Home shows one count: "Today: N cards left". Study now reads "Go through today's cards now" with no number | |
| [ ] | The topic badges on Home add up to "Today: N cards left"; subfolder badges add up to their topic's | |
| [ ] | Answer the last ready card Wrong: Study now says "Nothing to study yet · Cards you just answered come back later" while the top row still counts it | |
| [ ] | After the last notification, with cards ready: the top row says "All done for today" and Study now says "Get ahead on tomorrow's cards" | |
| [ ] | A folder's own Study now reads "Go through this folder's cards now" | |
| [ ] | After 5:15 PM, Study now and notifications start no new cards (their 3-hour check wouldn't fit); new cards earlier in the day get a check notification the same day | |

## Phase 3.13: Pause and Focus folders

| ✓ | Test | Notes |
|---|---|---|
| [ ] | Long-press a topic → Pause: its row turns grey with a pause icon, its badge goes, and "Today: N cards left" drops by its cards | |
| [ ] | No notifications arrive with a paused folder's cards; Resume brings them back into the plan (Today screen) | |
| [ ] | Long-press → Focus: the target icon appears, every other topic dims, and notifications only bring that folder's cards | |
| [ ] | Focus two folders (e.g. a topic and a subfolder in another topic): both come up, and the topic holding the subfolder isn't dimmed | |
| [ ] | Pause a subfolder inside a focused topic: its cards stay out | |
| [ ] | Open a paused folder: its Study now still works ("Go through this folder's cards now") | |
| [ ] | The Pause / Focus options are also in the + menu inside a folder | |
| [ ] | Pause and focus survive quitting and reopening the app; deleting a focused folder brings everything else back | |

## App icon

| ✓ | Test | Notes |
|---|---|---|
| [ ] | The home screen shows the StudyUp icon (white cards with a blue line, on blue) | |
| [ ] | Reminders show the icon instead of a blank square | |
| [ ] | Home screen set to Dark, then Tinted (long-press the home screen → Edit → Customize): the icon has a version for each | |

## Feel and feedback

Real use is what settles these defaults. The app's defaults are up to 8 reminders a day, 3 cards each, 9 AM – 9 PM, and 10 new cards a day; your phone is currently set to 1 card per reminder.

| Question | Answer |
|---|---|
| Too many or too few reminders per day? | |
| How many cards per reminder feels right (1? 3?)? | |
| Are the notification sound and banner annoying, or fine? | |
| Anything slow or clunky when adding cards on the phone? | |

## Bugs found

| Date | What happened | Status |
|---|---|---|
| 2026-10-26 | Evening Home read "Today: 3 cards left" with "No more notifications today · next tomorrow at 9:45". The 3 cards came due at 8:58–8:59 PM, after the last notification (8:15 PM), so they were really tomorrow's | Fixed 2026-10-27 (Phase 3.12) |
| 2026-10-27 | Notifications show the blank default icon instead of the app icon | Build number raised 1 → 2 so iOS refreshes its icon cache; if it persists after ⌘R, restart the iPhone |
| | | |
