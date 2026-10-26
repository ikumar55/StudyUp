# StudyUp

A personal flashcard app for studying through the day. Cards live in nested folders; the iPhone app sends a few cards at a time as notifications, and spaced repetition (FSRS) decides what comes up when. You answer right from the notification, or open the app. A web editor on the Mac is for writing cards (with images, code, LaTeX math, and cloze blanks), and it syncs with the phone over Wi-Fi. No account and no cloud: your cards stay on your devices.

- **iPhone app:** SwiftUI + SwiftData, iOS 26.5+, in `StudyUp/` (plus a notification extension and `Shared/`)
- **Mac web app:** Node + TypeScript server with SQLite, and a React editor, in `web/` (see [web/README.md](web/README.md))

## Getting started

1. **iPhone:** connect the iPhone to the Mac with a cable, open `StudyUp.xcodeproj` in Xcode, choose the **StudyUp** scheme and your iPhone (or a simulator), and press ⌘R. A free Apple developer account works; reinstall every 7 days.
2. **Mac:** install Node (`brew install node`), then run `web/scripts/install-service.sh`. The editor runs at http://localhost:8787 and starts at login.
3. **Pair:** in the editor, click **Pair an iPhone**. In the app, go to **Settings → Sync with Mac** and enter the code.

## Everyday use

**The Mac editor runs by itself.** `install-service.sh` sets it up as a background service: it starts when you log in, restarts itself if it crashes, and keeps running after you close the browser, VS Code, or the terminal. Just open http://localhost:8787 (worth a bookmark).

- **Not loading?** Run `~/Desktop/StudyUp/web/scripts/install-service.sh` in Terminal. It rebuilds and restarts the service, and is always safe to run. The log is at `~/Library/Logs/StudyUp/server.log`.
- **Syncing** needs the Mac awake and on the same Wi-Fi as the phone. No window has to be open.
- **Your data** lives in `~/Library/Application Support/StudyUp/`: the database, images, and a daily backup in `backups/` (the last 14 days).
- To stop the service for good: `web/scripts/uninstall-service.sh` (your cards are kept).

**Updating the iPhone app** (after changes, or when it stops opening after 7 days on a free account):

1. Connect the iPhone with a cable (USB-C on iPhone 15 and later, Lightning on earlier models) and unlock it.
2. Open `StudyUp.xcodeproj` in **Xcode** (not VS Code), choose the **StudyUp** scheme and your iPhone at the top.
3. Press **⌘R**. The app is updated in place; your cards and progress stay.

Once the phone has been connected by cable, Xcode can often install over Wi-Fi too: check **Window → Devices and Simulators** for your iPhone with a network icon or a "Connect via network" option.

## Docs

- [PLAN.md](PLAN.md): goals, decisions, roadmap, and what's done
- [CLAUDE.md](CLAUDE.md): architecture, conventions, and commands (written for Claude Code, useful for anyone)
- [TESTING.md](TESTING.md): what to check on a real iPhone
