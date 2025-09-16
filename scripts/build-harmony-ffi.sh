#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
FFI_DIR="$ROOT/harmony-ffi"
OUT_DIR="$ROOT/third_party/harmony-ffi/build"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust toolchain (e.g., rustup)." >&2
  exit 2
fi

echo "Building harmony-ffi..."
(cd "$FFI_DIR" && cargo build --release)

mkdir -p "$OUT_DIR"
cp -f "$FFI_DIR/target/release/libharmony_ffi.a" "$OUT_DIR/"
cp -f "$ROOT/daemon-swift/Sources/HarmonyFFI/include/harmony_ffi.h" "$OUT_DIR/"

echo
echo "Exports:"
echo "  export HARMONY_FFI_INCLUDE_DIR=$OUT_DIR"
echo "  export HARMONY_FFI_LIB_DIR=$OUT_DIR"

