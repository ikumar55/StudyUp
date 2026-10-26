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
| [ ] | The home screen offers "Turn On Study Reminders", and the iOS permission prompt appears | |
| [ ] | Home shows "Next reminder today at …" after allowing notifications | |
| [ ] | Settings → Send a Test Reminder arrives about 5 seconds later, **with the phone locked** | |
| [ ] | Tapping a reminder opens Quick Review starting with **that** card | |
| [ ] | Quick Review stops after "cards per reminder", and Keep Going continues | |
| [ ] | **Long-press** a reminder: the answer appears, and the buttons say when the card comes back ("Right · in a few hours") | |
| [ ] | Grading from the long-press **without opening the app**, then opening the app, shows the card as reviewed | |
| [ ] | Grading from a notification while the phone is **locked** works (may ask for Face ID) | |
| [ ] | Tap a reminder while a card editor is open **with nothing typed**: the editor closes and Quick Review opens | |
| [ ] | Tap a reminder while **writing** a card: the editor stays, with a note that the reminder's cards open when you're done; after Add (or Cancel → Discard), Quick Review opens | |
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
| [ ] | A code block starting with ```c (or python, js, swift…) shows syntax colors on both sides | |
| [ ] | Download backup: the file includes an "images" section | |

## Phase 3.6: Today view and card progress

| ✓ | Test | Notes |
|---|---|---|
| [ ] | The card editor no longer has "Add and Start Next Card"; Add saves and closes | |
| [ ] | Study buttons say: Wrong · "next reminder", Right on a new card · "in a few hours", Right on a learned card · "in N days" | |
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
| | | |
