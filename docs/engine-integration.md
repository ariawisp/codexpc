# Engine Integration

The daemon calls the GPT‑OSS Metal C API. You have two options:

1) Use the upstream headers and link to a prebuilt libgptoss.
2) Build gpt‑oss/metal locally and link to the resulting static or dynamic library.

## Env vars

Option A: Build GPT‑OSS locally using the helper script, then build the daemon.

```
cd ../codexpc
./scripts/build-gptoss-macos.sh [../gpt-oss/gpt_oss/metal]
cd daemon-swift
GPTOSS_INCLUDE_DIR=$GPTOSS_INCLUDE_DIR GPTOSS_LIB_DIR=$GPTOSS_LIB_DIR swift build -c release
```

Option B: Set env vars manually when invoking `swift build`:

```
export GPTOSS_INCLUDE_DIR=/path/to/gpt-oss/metal/include
export GPTOSS_LIB_DIR=/path/to/build/lib
```

And pass:

```
swift build -Xcc -I$GPTOSS_INCLUDE_DIR \
           -Xlinker -L$GPTOSS_LIB_DIR \
           -Xlinker -lgptoss
```

## Sanity checks

- Verify the symbol `gptoss_model_create_from_file` is resolvable (e.g., `nm -g libgptoss.a | grep gptoss_model_create_from_file`).
- Verify headers under `gpt-oss/include/gpt-oss/*.h` are visible to the Swift target.

## Harmony formatter via official C API

Use the first‑class Harmony C API from the `../harmony` repository. Build the static or dynamic library and point SwiftPM at its include and lib directories.

```
# Build Harmony static/dynamic libraries
cd ../harmony
cargo build --release --target aarch64-apple-darwin

# Back in codexpc, export include/lib dirs
cd ../codexpc
export HARMONY_INCLUDE_DIR=$PWD/../harmony/include
export HARMONY_LIB_DIR=$PWD/../harmony/target/aarch64-apple-darwin/release

# Build daemon linking libopenai_harmony
cd daemon-swift && swift build -c release
```

The daemon links `libopenai_harmony` and uses it to render Harmony conversations (system + user messages) into token IDs compatible with GPT‑OSS.
