# CodexPC Handoff Plan (Current)

Highlights of the update
- Reflects event‑driven Harmony decoding (no raw‑decode fallback), unlimited tokens only, and guarded stop behavior.
- Documents Makefile targets for install/health/smoke/logs/reload/warmup.
- Clarifies “Where Things Live” and adds sibling repo pointers.
- Prioritized “Next Engineer Plan” shifts to Harmony event/option completion and tool registry + validation.

What changed in this version
- Title updated to “Current”.
- Runbook now lists Make targets and the expected log lines.
- Next‑step priorities:
  - Harmony event API: emit TOOL_ARGS_DONE/STOP; honor CompletionOptions internally.
  - Tool registry + JSON‑schema validation: Codex → Harmony → daemon.
  - Packaging polish for rpath.
  - Optional dynamic batch sizing.

Paths referenced
- codexpc daemon: `daemon-swift/`
- Harmony Swift shim headers: `daemon-swift/Sources/OpenAIHarmony/`
- Streaming core: `daemon-swift/Sources/codexpcCore/` {`MetalRunner.swift`,`SessionManager.swift`,`Harmony*`}
- Codex provider: `../codex/codex-rs/core/src/codexpc.rs`
- Harmony C API repo: `../harmony`
- GPT‑OSS (Metal engine): `../gpt-oss/gpt_oss/metal`

Prompt For Next Agent
Use this as your kickoff message to the next engineer:

—
Context and Starting Points

- Handoff plan: `docs/HANDOFF_PLAN.md`
- Sibling repos:
  - Codex (Rust provider & tests): `../codex/codex-rs`
  - Harmony (C API + encoder/decoder): `../harmony`
  - GPT‑OSS (Metal engine): `../gpt-oss/gpt_oss/metal`

Current State (What Works)

- XPC daemon streams Created → final-only deltas → tool events → Completed. Unlimited tokens only; stops on Harmony stop tokens. Guarded stop is enforced.
- Decoder is event-driven via Harmony C API `harmony_streamable_parser_next_event`. No raw-decode fallback.
- Packaging installs codexpcd as a LaunchAgent, embeds metallib, and sets Harmony dylib to @rpath in the installer.
- Codex macOS provider uses XPC; integration tests pass.

Your Goals (Prioritized)

1. Complete Harmony event API and options
   - Emit TOOL_ARGS_DONE and STOP in Harmony’s next_event.
   - Honor HarmonyCompletionOptions (final_only_deltas, guarded_stop, tools_json) inside Harmony.
   - Remove equivalent Swift-side policy once Harmony enforces it.
2. Tool registry + schema validation
   - Plumb tool registry (names + JSON schemas) from Codex → Harmony → daemon.
   - Validate tool arguments pre-execution; emit clear structured failures via XPC.
3. Packaging polish
   - Keep installer’s @rpath rewrite. Optionally make Harmony build set install_name robustly to reduce the need for post-install fixes.
4. Optional: dynamic batch sizing
   - Compute safe batch clamp from device memory/model dims.

Acceptance

- CLI health/smoke (unlimited tokens) reliable; second run is immediate (engine cache hit).
- Unified logs: stream start → sample rc/out → first delta; no fallback logs.
- Codex macOS integration tests pass with your checkpoint; tool args get validated when registry is present.
- Harmony dylib @rpath; metallib embedded (__METAL,__shaders present).

Runbook

- Install: `make install`
- Health: `make health`
- Smoke (unlimited): `make smoke CHECKPOINT="$HOME/gpt-oss-20b/metal/model.bin"`
- Logs: `make logs LAST=10m`
- Codex test: `make codex-test CHECKPOINT="$HOME/gpt-oss-20b/metal/model.bin"`
  - Expected unified log lines:
    - `harmony append tokens=… user_parts=…`
    - `HarmonyStreamDecoder initialized`
    - `stream start temp=… max=… harmony=true`
    - `sample rc=… out=…`
    - `first delta len=…`
    - Event‑driven only (no raw‑decode fallback)

Troubleshooting

- No deltas: check logs for “sample rc/out” and “first delta”; confirm metallib is embedded; verify Harmony dylib is resolvable.
- Immediate completed without text: ensure scaffold steers final channel; adjust if necessary.
- Memory: consider lowering batch for low-RAM devices.

Notes

- No runtime envs for production; tools disabled by default; allowlist is code-only. Test hooks exist but should not leak to prod paths.
- Non-Harmony builds are not supported; decoder requires Harmony event API.

Where Things Live
- Daemon: `daemon-swift/` (XPC server, engine bridge, Harmony integration)
- Engine bridge: `daemon-swift/Sources/codexpcEngine/`
- Harmony Swift shim: `daemon-swift/Sources/OpenAIHarmony/`
- Streaming core: `daemon-swift/Sources/codexpcCore/MetalRunner.swift`, `SessionManager.swift`, `Harmony*`
- Installer/LaunchAgent: `packaging/`
- Codex provider: `../codex/codex-rs` (XPC in `codexpc-xpc`, provider in `core/src/codexpc.rs`)
- Harmony repo (C API + encoder/decoder): `../harmony`
- GPT‑OSS Metal engine: `../gpt-oss/gpt_oss/metal`
