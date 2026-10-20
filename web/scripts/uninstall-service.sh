#!/bin/zsh
# Stops the StudyUp background service and removes it from login. Your cards are kept in
# ~/Library/Application Support/StudyUp/studyup.db.
set -euo pipefail

LABEL="com.ikumar55.studyup.server"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Library/Application Support/StudyUp/app"
echo "StudyUp's background service is removed. Your cards are still in ~/Library/Application Support/StudyUp/studyup.db"
