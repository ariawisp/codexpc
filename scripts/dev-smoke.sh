#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
CHECKPOINT="${CHECKPOINT:-$HOME/gpt-oss-20b/metal/model.bin}"

echo "Installing/Reloading LaunchAgent..."
"$ROOT/packaging/install-agent.sh"

echo "Health check..."
(cd "$ROOT/cli-swift" && swift run -c release codexpc-cli --health)

echo "Smoke stream (checkpoint: $CHECKPOINT)..."
(cd "$ROOT/cli-swift" && swift run -c release codexpc-cli --checkpoint "$CHECKPOINT" --prompt "hello" --temperature 0.0 --max-tokens 0)
