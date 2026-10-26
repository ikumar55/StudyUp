# StudyUp web app (Mac)

Write and organize flashcards in your browser. They sync to the StudyUp iPhone app over Wi-Fi.

- **Server** (`server/`): Node + TypeScript (run directly by Node 24+, no build step) with a SQLite database at `~/Library/Application Support/StudyUp/studyup.db` and a daily snapshot of it in `backups/` next to it (the last 14 days). It serves the editor at http://localhost:8787 to this Mac only. Other devices on the network can only pair (`/pair`) and sync (`/sync`), and only with a token. It announces itself over Bonjour as `_studyup._tcp` so the phone can find it.
- **Editor** (`client/`): React + Vite.
- **Shared types** (`shared/protocol.ts`): the sync format, mirrored in Swift by `StudyUp/Sync/SyncProtocol.swift`.

## Everyday use

```bash
./scripts/install-service.sh     # build, install, and start at login (run again after changing the code)
open http://localhost:8787
./scripts/uninstall-service.sh   # stop it and remove it from login (your cards are kept)
```

To pair your iPhone: in the editor, click **Pair an iPhone**. Then, in the app, go to **Settings → Sync with Mac**, choose your Mac, and enter the code. After that, the phone syncs whenever you open or leave the app while it's on the same Wi-Fi as the Mac.

## Development

```bash
npm install
npm run dev:server    # API on :8787, restarts on change
npm run dev:client    # editor on :5173 with hot reload, proxying /api to :8787
npm test              # server tests (sync rules, pairing, API)
npm run typecheck
npm run build         # editor → client/dist, served by the server
```

To use a throwaway database, set `STUDYUP_DB=/path/to/test.db` (and `PORT=…`) when starting the server.

End-to-end sync test with the iPhone simulator:

```bash
STUDYUP_DB=/tmp/studyup-test.db PORT=8799 node server/index.ts &
cd .. && TEST_RUNNER_STUDYUP_SERVER=http://localhost:8799 xcodebuild test -project StudyUp.xcodeproj \
  -scheme StudyUp -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:StudyUpTests/SyncIntegrationTests
```
