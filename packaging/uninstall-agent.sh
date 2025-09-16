#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.yourorg.codexpc.plist"

launchctl stop com.yourorg.codexpc || true
launchctl unload "$PLIST_DST" || true

# Attempt to remove installed binary based on ProgramArguments
BIN_PATH=""
if [ -f "$PLIST_DST" ]; then
  BIN_PATH=$( /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$PLIST_DST" 2>/dev/null || true )
fi

rm -f "$PLIST_DST"

if [ -n "$BIN_PATH" ] && [ -f "$BIN_PATH" ]; then
  rm -f "$BIN_PATH" || true
  echo "Removed binary: $BIN_PATH"
fi

# Clean symlink
if [ -L "/usr/local/bin/codexpcd" ]; then
  rm -f "/usr/local/bin/codexpcd" || true
  echo "Removed symlink: /usr/local/bin/codexpcd"
fi

echo "Removed LaunchAgent."
