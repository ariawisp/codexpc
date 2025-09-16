#!/usr/bin/env bash
set -euo pipefail

# Build the GPT-OSS Metal library for macOS and print env exports for Swift build.

ROOT="$(cd "$(dirname "$0")"/.. && pwd)"
SRC_DEFAULT="$ROOT/../gpt-oss/gpt_oss/metal"
SRC="${1:-$SRC_DEFAULT}"

if [[ ! -d "$SRC" ]]; then
  echo "error: source dir not found: $SRC" >&2
  echo "usage: $0 [/path/to/gpt_oss/metal]" >&2
  exit 2
fi

BUILD_DIR="$ROOT/third_party/gptoss/build"
mkdir -p "$BUILD_DIR"

echo "Configuring GPT-OSS Metal in $BUILD_DIR (source: $SRC)"
cmake -S "$SRC" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DPYBIND11_FINDPYTHON=ON -DPython3_EXECUTABLE="$(command -v python3)"
echo "Building libgptoss..."
cmake --build "$BUILD_DIR" --target gptoss --config Release -j

# Find the built library
LIB_PATH=$(find "$BUILD_DIR" -name 'libgptoss.a' -print -quit)
if [[ -z "${LIB_PATH:-}" ]]; then
  echo "error: libgptoss.a not found under $BUILD_DIR" >&2
  exit 3
fi
LIB_DIR="$(cd "$(dirname "$LIB_PATH")" && pwd)"
INC_DIR="$SRC/include"

echo
echo "OK. To build the daemon against GPT-OSS, run:" 
echo "  cd $ROOT/daemon-swift && GPTOSS_INCLUDE_DIR=$INC_DIR GPTOSS_LIB_DIR=$LIB_DIR swift build -c release"
echo
echo "Exports (for convenience):"
echo "  export GPTOSS_INCLUDE_DIR=$INC_DIR"
echo "  export GPTOSS_LIB_DIR=$LIB_DIR"
