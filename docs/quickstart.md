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

## Use the Swift CLI for a quick smoke test

Build and run the CLI:

```
cd ../cli-swift
swift run -c release codexpc-cli --checkpoint /path/to/model.bin --prompt "hello" --temperature 0.0 --max-tokens 64
```

```
