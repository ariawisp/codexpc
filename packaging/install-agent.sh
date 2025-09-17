#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.yourorg.codexpc.plist"
ROOT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"

echo "Preparing build prerequisites..."
# Resolve GPT-OSS headers and libs (auto-build if missing)
DEFAULT_GPTOSS_INCLUDE_DIR="$ROOT_DIR/../gpt-oss/gpt_oss/metal/include"
DEFAULT_GPTOSS_LIB_DIR="$ROOT_DIR/third_party/gptoss/build"
GPTOSS_INCLUDE_DIR="${GPTOSS_INCLUDE_DIR:-$DEFAULT_GPTOSS_INCLUDE_DIR}"
GPTOSS_LIB_DIR="${GPTOSS_LIB_DIR:-$DEFAULT_GPTOSS_LIB_DIR}"
if [ ! -f "$GPTOSS_LIB_DIR/libgptoss.a" ] || [ ! -f "$GPTOSS_LIB_DIR/default.metallib" ]; then
  echo "Building GPT-OSS (first run)..."
  (cd "$ROOT_DIR/scripts" && ./build-gptoss-macos.sh "$DEFAULT_GPTOSS_INCLUDE_DIR")
fi

# Resolve and build Harmony C API (required)
DEFAULT_HARMONY_INCLUDE_DIR="$ROOT_DIR/../harmony/include"
DEFAULT_HARMONY_LIB_DIR="$ROOT_DIR/../harmony/target/aarch64-apple-darwin/release"
HARMONY_INCLUDE_DIR="${HARMONY_INCLUDE_DIR:-$DEFAULT_HARMONY_INCLUDE_DIR}"
HARMONY_LIB_DIR="${HARMONY_LIB_DIR:-$DEFAULT_HARMONY_LIB_DIR}"

echo "Building Harmony (required)..."
"$ROOT_DIR/scripts/build-harmony-ffi.sh"
export HARMONY_INCLUDE_DIR HARMONY_LIB_DIR
if [ ! -f "$HARMONY_LIB_DIR/libopenai_harmony.dylib" ]; then
  echo "error: Harmony build did not produce libopenai_harmony.dylib in $HARMONY_LIB_DIR" >&2
  exit 3
fi

export GPTOSS_INCLUDE_DIR GPTOSS_LIB_DIR

echo "Building codexpcd (release)..."
(cd "$ROOT_DIR/daemon-swift" && swift build -c release)

# Choose install dir (prefer /opt; fallback to ~/.local)
PREF_DEST_DIR="/opt/codexpc/bin"
ALT_DEST_DIR="$HOME/.local/codexpc/bin"
DEST_DIR="$PREF_DEST_DIR"
if ! mkdir -p "$PREF_DEST_DIR" 2>/dev/null; then
  echo "warn: insufficient permissions for $PREF_DEST_DIR, using $ALT_DEST_DIR" >&2
  DEST_DIR="$ALT_DEST_DIR"
  mkdir -p "$DEST_DIR"
fi
BIN_PATH="$DEST_DIR/codexpcd"

echo "Installing binary to $BIN_PATH"
cp -f "$ROOT_DIR/daemon-swift/.build/release/codexpcd" "$BIN_PATH"
chmod +x "$BIN_PATH"

# Install runtime resources next to the binary (../lib and ../share/codexpc)
BASE_DIR="$(cd "$DEST_DIR/.." && pwd)"
LIB_DIR="$BASE_DIR/lib"
SHARE_DIR="$BASE_DIR/share/codexpc"
mkdir -p "$LIB_DIR" "$SHARE_DIR"
if [ -n "${HARMONY_LIB_DIR:-}" ] && [ -f "$HARMONY_LIB_DIR/libopenai_harmony.dylib" ]; then
  cp -f "$HARMONY_LIB_DIR/libopenai_harmony.dylib" "$LIB_DIR/"
fi
if [ -n "${GPTOSS_LIB_DIR:-}" ] && [ -f "$GPTOSS_LIB_DIR/default.metallib" ]; then
  cp -f "$GPTOSS_LIB_DIR/default.metallib" "$SHARE_DIR/default.metallib"
fi

# Create a convenience symlink if possible
SYMLINK="/usr/local/bin/codexpcd"
if ln -sfn "$BIN_PATH" "$SYMLINK" 2>/dev/null; then
  echo "Created symlink $SYMLINK -> $BIN_PATH"
else
  echo "note: could not create $SYMLINK symlink (permission denied?)." >&2
fi

echo "Writing LaunchAgent to $PLIST_DST"
mkdir -p "$(dirname "$PLIST_DST")"
cat >"$PLIST_DST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.yourorg.codexpc</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN_PATH}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>GPTOSS_WEIGHTS_PRIVATE</key>
    <string>1</string>
    <key>GPTOSS_DISABLE_MLOCK</key>
    <string>1</string>
    <key>CODEXPC_MAX_BATCH_TOKENS</key>
    <string>32</string>
  </dict>
  <key>MachServices</key>
  <dict>
    <key>com.yourorg.codexpc</key>
    <true/>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/com.yourorg.codexpc.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/com.yourorg.codexpc.err.log</string>
</dict>
</plist>
PLIST

echo "Reloading LaunchAgent..."
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load -w "$PLIST_DST"
launchctl start com.yourorg.codexpc || true

echo "Done. Service: com.yourorg.codexpc"
echo "Binary: $BIN_PATH"
if [ -L "$SYMLINK" ]; then echo "Symlink: $SYMLINK -> $(readlink "$SYMLINK")"; fi
echo "Check status: launchctl list | grep codexpc"
echo "Logs: $HOME/Library/Logs/com.yourorg.codexpc.*.log"

# Helpful hints for engine integration
if [ -z "${GPTOSS_LIB_DIR:-}" ] || [ -z "${GPTOSS_INCLUDE_DIR:-}" ]; then
  echo "note: GPTOSS_* env vars not set. If link failed earlier, run scripts/build-gptoss-macos.sh and rebuild." >&2
fi
if [ -z "${HARMONY_LIB_DIR:-}" ] || [ -z "${HARMONY_INCLUDE_DIR:-}" ]; then
  echo "note: Harmony C API not built. To enable Harmony formatting, run scripts/build-harmony-ffi.sh and rebuild." >&2
fi
