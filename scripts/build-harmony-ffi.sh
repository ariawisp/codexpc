#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
HARMONY_DIR="$ROOT/../harmony"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust toolchain (e.g., rustup)." >&2
  exit 2
fi

echo "Building Harmony (libopenai_harmony)..."
# Align Harmony's deployment target with the host/toolchain (or user override)
TARGET_MINOS="${MACOSX_DEPLOYMENT_TARGET:-}"
if [ -z "$TARGET_MINOS" ]; then
  TARGET_MINOS="$(xcrun --sdk macosx --show-sdk-platform-version 2>/dev/null || xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
fi
if [ -n "$TARGET_MINOS" ]; then
  export MACOSX_DEPLOYMENT_TARGET="$TARGET_MINOS"
  # Also instruct Rust linker explicitly
  export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
  echo "Harmony build MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
fi
(cd "$HARMONY_DIR" && cargo build --release --target aarch64-apple-darwin)

INC_DIR="$HARMONY_DIR/include"
LIB_DIR="$HARMONY_DIR/target/aarch64-apple-darwin/release"

echo
echo "Exports:"
echo "  export HARMONY_INCLUDE_DIR=$INC_DIR"
echo "  export HARMONY_LIB_DIR=$LIB_DIR"
