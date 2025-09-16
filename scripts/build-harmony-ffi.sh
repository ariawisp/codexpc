#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
HARMONY_DIR="$ROOT/../harmony"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust toolchain (e.g., rustup)." >&2
  exit 2
fi

echo "Building Harmony (libopenai_harmony)..."
(cd "$HARMONY_DIR" && cargo build --release --target aarch64-apple-darwin)

INC_DIR="$HARMONY_DIR/include"
LIB_DIR="$HARMONY_DIR/target/aarch64-apple-darwin/release"

echo
echo "Exports:"
echo "  export HARMONY_INCLUDE_DIR=$INC_DIR"
echo "  export HARMONY_LIB_DIR=$LIB_DIR"
