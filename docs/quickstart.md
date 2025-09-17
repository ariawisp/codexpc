# Quickstart

This guide brings up `codexpcd` locally and exercises a text-only stream.

## Build the daemon

```
cd daemon-swift
swift build -c debug
```

Run it in a terminal:

```
./.build/debug/codexpcd
```

## Ping using a tiny test client (Swift)

While the Kotlin/Native client is being built, you can test the daemon via `xpc_connection_create_mach_service` in a short Swift snippet (see `docs/swift-ping.md`).

## Install LaunchAgent

```
../packaging/install-agent.sh
```

To tail logs:

```
log stream --predicate 'subsystem == "com.yourorg.codexpc"'
```

## Use the Swift CLI for a quick smoke test

Build and run the CLI:

```
cd ../cli-swift
swift run -c release codexpc-cli --checkpoint /path/to/model.bin --prompt "hello" --temperature 0.0 --max-tokens 64
```

You can also ping health without a model:

```
swift run -c release codexpc-cli --health
```

Install locations:
- Binary: `/opt/codexpc/bin/codexpcd` (fallback: `~/.local/codexpc/bin/codexpcd`)
- Symlink (if possible): `/usr/local/bin/codexpcd`
- LaunchAgent: `~/Library/LaunchAgents/com.yourorg.codexpc.plist`

## Tool execution (demo)

Tool calls are disabled by default. To enable the demo tools and keep them safe:

- `CODEXPC_ALLOW_TOOLS=1` — enable tool execution
- `CODEXPC_ALLOWED_TOOLS="echo,upper"` — optional allowlist
- `CODEXPC_TOOL_TIMEOUT_MS=2000` — per-call timeout (ms)
- `CODEXPC_TOOL_MAX_OUTPUT_BYTES=8192` — cap output size (bytes)

Testing helpers:

- `CODEXPC_TEST_FORCE_TOOL="name:{\"msg\":\"text\"}"` — force a tool call
- `CODEXPC_TEST_TOOL_DELAY_MS=50` — simulate a slow tool for timeout testing

Note: Harmony C API is required (no stub). Use `scripts/build-harmony-ffi.sh` before building.
