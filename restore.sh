#!/bin/bash
# Reinstall the customized build over whatever is in /Applications.
# Run this whenever the app gets replaced by a stock release and the icon /
# dropdown revert to the defaults:   ~/claude-codex-battery/restore.sh
set -e
cd "$(dirname "$0")"
APP="/Applications/ClaudeCodexBattery.app"
BUILT="app/ClaudeCodexBattery.app"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "local-customizations" ]; then
  echo "⚠️  On branch '$BRANCH' — the customizations live on 'local-customizations'."
  echo "    Run: git checkout local-customizations"
  exit 1
fi

echo "🔨 Building from $(pwd) ($(git log --oneline -1))"
bash app/build.sh >/dev/null
echo "✅ build ok"

# Sanity check before touching /Applications — a build that cannot even print its
# menu is not worth installing over a working copy
"$BUILT/Contents/MacOS/ClaudeCodexBattery" --dump-menu >/dev/null 2>&1 \
  && echo "✅ smoke test ok" || { echo "❌ built app failed to run — not installing"; exit 1; }

if [ -d "$APP" ]; then
  osascript -e 'quit app "ClaudeCodexBattery"' 2>/dev/null || true
  pkill -x ClaudeCodexBattery 2>/dev/null || true
  sleep 1
  rm -rf "$APP"
fi
ditto "$BUILT" "$APP"
codesign --verify --deep --strict "$APP" && echo "✅ signature ok"

open -a "$APP"
sleep 2
pgrep -x ClaudeCodexBattery >/dev/null && echo "✅ restored and running" || echo "⚠️  installed but not running — launch it from Applications"
