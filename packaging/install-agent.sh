#!/usr/bin/env bash
set -euo pipefail

PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/com.yourorg.codexpc.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.yourorg.codexpc.plist"

echo "Installing LaunchAgent to $PLIST_DST"
mkdir -p "$(dirname "$PLIST_DST")"
cp "$PLIST_SRC" "$PLIST_DST"

launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load -w "$PLIST_DST"
launchctl start com.yourorg.codexpc || true
echo "Done. Use 'launchctl list | grep codexpc' to check status."

