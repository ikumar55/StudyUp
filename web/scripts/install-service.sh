#!/bin/zsh
# Installs (or updates) the StudyUp server as a background service that starts at login.
#
# macOS doesn't let background services read ~/Desktop, ~/Documents or ~/Downloads without
# extra permission, so the app is copied to ~/Library/Application Support/StudyUp/app and runs
# from there. Run this again after changing the web app to update the installed copy.
set -euo pipefail

LABEL="com.ikumar55.studyup.server"
WEB_DIR="${0:A:h:h}"
SUPPORT_DIR="$HOME/Library/Application Support/StudyUp"
APP_DIR="$SUPPORT_DIR/app"
LOG_DIR="$HOME/Library/Logs/StudyUp"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
NODE="$(command -v node || true)"
PORT="${PORT:-8787}"

if [[ -z "$NODE" ]]; then
  echo "Node.js isn't installed. Install it with: brew install node" >&2
  exit 1
fi

echo "Building the web app…"
(cd "$WEB_DIR" && npm install --silent && npm run build --silent)

echo "Copying it to $APP_DIR…"
mkdir -p "$APP_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
rsync -a --delete \
  --exclude 'server/test' --exclude 'client/src' --exclude 'scripts' --exclude '*.test.ts' \
  "$WEB_DIR/package.json" "$WEB_DIR/package-lock.json" "$WEB_DIR/shared" "$WEB_DIR/server" "$WEB_DIR/client" \
  "$APP_DIR/"
(cd "$APP_DIR" && npm install --silent --omit=dev)

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$NODE</string>
    <string>$APP_DIR/server/index.ts</string>
  </array>
  <key>WorkingDirectory</key><string>$APP_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PORT</key><string>$PORT</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG_DIR/server.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/server.log</string>
</dict>
</plist>
PLIST

# Restart the service so it runs the new copy.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

for _ in {1..20}; do
  if curl -fs "http://localhost:$PORT/health" >/dev/null; then
    echo "StudyUp is running at http://localhost:$PORT and will start automatically when you log in."
    echo "Logs: $LOG_DIR/server.log"
    exit 0
  fi
  sleep 0.5
done
echo "The service was installed but isn't answering yet. Check $LOG_DIR/server.log" >&2
exit 1
