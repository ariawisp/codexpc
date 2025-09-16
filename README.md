# codexpc

Local macOS XPC daemon and client for GPT‑OSS inference on Apple Silicon.

- Transport: libxpc (Mach service LaunchAgent)
- Daemon: Swift + ObjC++ bridge to GPT‑OSS Metal C API
- Client: Kotlin/Native via Objective‑C/C interop to libxpc

This repo is macOS‑only and focuses on low‑latency local inference. It does not depend on HTTP/SSE.

## Layout

- `daemon-swift/` — SwiftPM workspace containing the XPC daemon and core
- `daemon-swift/Sources/codexpcEngine/` — ObjC++/C headers and bridge (Swift target `codexpcEngine`)
- `client-kotlin-native/` — Kotlin/Native client library that speaks libxpc
- `cli/` — Minimal debug CLI built on the K/N client
- `protocol/` — Protocol docs and JSON samples
- `packaging/` — LaunchAgent plist and install scripts
- `docs/` — Quickstart and deeper design notes

## Quick start (daemon)

Prereqs:
- Xcode command line tools
- A built GPT‑OSS Metal library + headers (or build from source)

Build daemon:

```
cd daemon-swift
swift build -c release
```

Run in foreground for dev:

```
./.build/release/codexpcd
```

Install LaunchAgent:

```
../packaging/install-agent.sh
```

## Wiring the GPT‑OSS engine

The Swift target `codexpcEngine` expects to find the GPT‑OSS headers and library. Point to your build via environment vars when building:

```
export GPTOSS_INCLUDE_DIR=/path/to/gpt-oss/metal/include
export GPTOSS_LIB_DIR=/path/to/build/lib
swift build -c release \
  -Xcc -I$GPTOSS_INCLUDE_DIR \
  -Xlinker -L$GPTOSS_LIB_DIR \
  -Xlinker -lgptoss
```

Alternatively, vendor a thin CMake build step that compiles the GPT‑OSS Metal library as part of your CI and sets up a pkg‑config file. See `docs/engine-integration.md`.

## Kotlin/Native client

See `client-kotlin-native/README.md` for cinterop setup and a basic streaming example.

## Protocol

Protocol overview and samples are in `protocol/`. The wire is libxpc dictionaries with these core fields in every message:
- `proto_version` (u16)
- `service` ("codexpc")
- `req_id` (uuid string)
- `ts_ns` (u64)
- `type` (string)

See `protocol/protocol.md` for request and event details.
