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

## Harmony formatter via Rust FFI (optional)

To avoid maintaining a Swift formatter for the Harmony message format, you can build a tiny Rust static lib that exposes a C ABI using the local Harmony crate.

```
cd ../codexpc
./scripts/build-harmony-ffi.sh
export HARMONY_FFI_INCLUDE_DIR=$PWD/third_party/harmony-ffi/build
export HARMONY_FFI_LIB_DIR=$PWD/third_party/harmony-ffi/build
cd daemon-swift && swift build -c release
```

The daemon will then link `libharmony_ffi.a` and use it to format the system prompt into segments of special tokens and text.
