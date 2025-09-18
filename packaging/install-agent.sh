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
# Align the app's deployment target with Harmony's to avoid ld warnings
MINOS="$({ otool -l "$HARMONY_LIB_DIR/libopenai_harmony.dylib" 2>/dev/null || true; } | awk '/LC_BUILD_VERSION/,/cmdsize/ { if ($1=="minos") { print $2; exit } }')"
if [ -z "$MINOS" ]; then
  # Fallback to SDK platform version
  MINOS="$(xcrun --sdk macosx --show-sdk-platform-version 2>/dev/null || xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
fi
if [ -n "$MINOS" ]; then
  echo "Using MACOSX_DEPLOYMENT_TARGET=$MINOS for codexpcd"
  (cd "$ROOT_DIR/daemon-swift" && MACOSX_DEPLOYMENT_TARGET="$MINOS" swift build -c release)
else
  (cd "$ROOT_DIR/daemon-swift" && swift build -c release)
fi

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

# Also install the foreground smoke binary for CLI fallback
SMOKE_PATH="$DEST_DIR/gptoss-smoke"
if [ -f "$ROOT_DIR/daemon-swift/.build/release/gptoss-smoke" ]; then
  echo "Installing gptoss-smoke to $SMOKE_PATH"
  cp -f "$ROOT_DIR/daemon-swift/.build/release/gptoss-smoke" "$SMOKE_PATH"
  chmod +x "$SMOKE_PATH"
fi

# Install runtime resources next to the binary (../lib and ../share/codexpc)
BASE_DIR="$(cd "$DEST_DIR/.." && pwd)"
LIB_DIR="$BASE_DIR/lib"
SHARE_DIR="$BASE_DIR/share/codexpc"
mkdir -p "$LIB_DIR" "$SHARE_DIR"
if [ -n "${HARMONY_LIB_DIR:-}" ] && [ -f "$HARMONY_LIB_DIR/libopenai_harmony.dylib" ]; then
  cp -f "$HARMONY_LIB_DIR/libopenai_harmony.dylib" "$LIB_DIR/"
  # Ensure the Harmony dylib uses @rpath for install_name so the executable can find it via rpath
  install_name_tool -id "@rpath/libopenai_harmony.dylib" "$LIB_DIR/libopenai_harmony.dylib" || true
fi
if [ -n "${GPTOSS_LIB_DIR:-}" ] && [ -f "$GPTOSS_LIB_DIR/default.metallib" ]; then
  cp -f "$GPTOSS_LIB_DIR/default.metallib" "$SHARE_DIR/default.metallib"
fi

# Optional warmup config: if a conventional checkpoint exists, seed a warmup-checkpoint file
ETC_DIR="$BASE_DIR/etc"
mkdir -p "$ETC_DIR"
DEFAULT_CKPT="$HOME/gpt-oss-20b/metal/model.bin"
if [ -f "$DEFAULT_CKPT" ]; then
  echo "$DEFAULT_CKPT" >"$ETC_DIR/warmup-checkpoint"
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
    <key>DYLD_LIBRARY_PATH</key>
    <string>${BASE_DIR}/lib</string>
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
</dict>
</plist>
PLIST

echo "Reloading LaunchAgent..."
# Proactively stop and bootout any existing instance to avoid stale processes
launchctl stop com.yourorg.codexpc 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.yourorg.codexpc 2>/dev/null || true
pkill -9 -x codexpcd 2>/dev/null || true
# Unload if present (ignore errors), then load fresh and kickstart
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load -w "$PLIST_DST"
launchctl kickstart -k gui/$(id -u)/com.yourorg.codexpc 2>/dev/null || true

# Adjust the binary's reference to Harmony dylib to use @rpath if needed
if otool -L "$BIN_PATH" | rg -q "libopenai_harmony"; then
  OLD_REF=$(otool -L "$BIN_PATH" | awk '/libopenai_harmony/ {print $1; exit}')
  if [ -n "$OLD_REF" ] && [ "$OLD_REF" != "@rpath/libopenai_harmony.dylib" ]; then
    echo "Rewriting Harmony dylib reference in codexpcd: $OLD_REF -> @rpath/libopenai_harmony.dylib"
    install_name_tool -change "$OLD_REF" "@rpath/libopenai_harmony.dylib" "$BIN_PATH" || true
  fi
  # Ensure the binary has an rpath pointing to our colocated lib dir
  if ! otool -l "$BIN_PATH" | rg -q "LC_RPATH[\s\S]*$BASE_DIR/lib"; then
    echo "Adding RPATH for Harmony dylib: $BASE_DIR/lib"
    install_name_tool -add_rpath "$BASE_DIR/lib" "$BIN_PATH" || true
  fi
fi

echo "Done. Service: com.yourorg.codexpc"
echo "Binary: $BIN_PATH"
if [ -L "$SYMLINK" ]; then echo "Symlink: $SYMLINK -> $(readlink "$SYMLINK")"; fi
echo "Check status: launchctl list | grep codexpc"
echo "Logs (unified log): use 'log show --predicate 'subsystem == \"com.yourorg.codexpc\"' --last 10m --info --debug'"
echo "Harmony dylib ref: $(otool -L "$BIN_PATH" | rg 'libopenai_harmony' -n || true)"
echo "Verify metallib embedded: otool -l \"$BIN_PATH\" | rg '__METAL|__shaders'"
