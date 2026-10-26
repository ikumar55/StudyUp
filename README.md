# StudyUp

A personal flashcard app for studying through the day. Cards live in nested folders; the iPhone app sends a few cards at a time as notifications, and spaced repetition (FSRS) decides what comes up when. You answer right from the notification, or open the app. A web editor on the Mac is for writing cards (with images, code, LaTeX math, and cloze blanks), and it syncs with the phone over Wi-Fi. No account and no cloud: your cards stay on your devices.

- **iPhone app:** SwiftUI + SwiftData, iOS 26.5+, in `StudyUp/` (plus a notification extension and `Shared/`)
- **Mac web app:** Node + TypeScript server with SQLite, and a React editor, in `web/` (see [web/README.md](web/README.md))

## Getting started

1. **iPhone:** open `StudyUp.xcodeproj` in Xcode, choose the **StudyUp** scheme and your iPhone (or a simulator), and press ⌘R. A free Apple developer account works; reinstall every 7 days.
2. **Mac:** install Node (`brew install node`), then run `web/scripts/install-service.sh`. The editor runs at http://localhost:8787 and starts at login.
3. **Pair:** in the editor, click **Pair an iPhone**. In the app, go to **Settings → Sync with Mac** and enter the code.

## Docs

- [PLAN.md](PLAN.md): goals, decisions, roadmap, and what's done
- [CLAUDE.md](CLAUDE.md): architecture, conventions, and commands (written for Claude Code, useful for anyone)
- [TESTING.md](TESTING.md): what to check on a real iPhone
