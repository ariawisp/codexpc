#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.yourorg.codexpc.plist"

launchctl stop com.yourorg.codexpc || true
launchctl unload "$PLIST_DST" || true
rm -f "$PLIST_DST"
echo "Removed LaunchAgent."

