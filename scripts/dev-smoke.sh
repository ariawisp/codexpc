#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")"/.. && pwd)"

echo "Building daemon..."
(cd "$ROOT/daemon-swift" && swift build -c debug)

echo "Starting daemon in background..."
"$ROOT/daemon-swift/.build/debug/codexpcd" &
DAEMON_PID=$!
trap 'kill $DAEMON_PID || true' EXIT

sleep 1

echo "Building CLI..."
(cd "$ROOT/cli-swift" && swift build -c release)

echo "Running CLI..."
"$ROOT/cli-swift/.build/release/codexpc-cli" --checkpoint "/path/to/model.bin" --prompt "hello"

