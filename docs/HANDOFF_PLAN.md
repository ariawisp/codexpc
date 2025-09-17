# CodexPC Handoff Plan (Updated)

Scope: codexpc (daemon-swift, packaging, scripts), codex (macOS provider + tests), gpt-oss (Metal C API), harmony (official C API).

This reflects the latest working state: XPC-only path, no runtime envs, Harmony final-only output with guarded stop, and Codex provider aligned to the same Harmony format.

## Current State (What Works)
- XPC daemon (Swift) as a per-user LaunchAgent (Mach service `com.yourorg.codexpc`).
  - Events: `created`, `output_text.delta`, `output_item.done` (tool_call/tool_call.output), `completed` (with token_usage).
  - Harmony: Formatter + stream decoder. Commentary suppressed; final-only output to clients. Guarded stop: continue past analysis until final/tool event. Fallback to raw decode if no deltas after 128 tokens.
  - Engine: GPT‑OSS Metal C API bridged via ObjC++; Private buffer uploads and mlock disabled are enforced in-process (no envs). Engine cache keyed by checkpoint avoids re-upload after first request.
  - Batch clamp: fixed conservative default (32) inside the engine.
- CLI (Swift): XPC-only; `--max-tokens 0` means unlimited (until EOS). Health ping supported.
- Packaging: Single installer builds GPT‑OSS + Harmony, embeds metallib into the binary, installs LaunchAgent. Logs to unified log (no file logs).
- Codex provider (../codex): macOS XPC path uses the same Harmony JSON shape (top-level `role`, typed content) and sends `harmony_conversation`. Unlimited tokens mapped to 0.

## Runbook (Operator)
- Install/Reload:
  - `../packaging/install-agent.sh`
- Health:
  - `cd cli-swift && swift run -c release codexpc-cli --health` → `health: ok`
- Stream smoke (20B model):
  - `swift run -c release codexpc-cli --checkpoint "$HOME/gpt-oss-20b/metal/model.bin" --prompt "hello" --temperature 0.0 --max-tokens 0`
  - Expect: `created`, final deltas, `completed`. First run pays one-time weight upload; subsequent runs stream immediately.
- Unified logs (useful lines):
  - `harmony append tokens=… user_parts=…`
  - `HarmonyStreamDecoder initialized`
  - `stream start temp=… max=… harmony=true`
  - `sample rc=… out=…`
  - `first delta len=…`
  - Optional: `decoder fallback: switching to raw decode …` (only if Harmony stays quiet >128 tokens)

## Design Notes (No Runtime Envs)
- Private uploads + mlock disabled are set programmatically in the engine bridge — stable under LaunchAgent.
- No `CODEXPC_*` or `GPTOSS_*` runtime envs are required. Build-time envs for headers/libs are handled by the installer.
- Tools are disabled by default; their configuration is code-only (no envs).

## Next Engineer Plan (Prioritized)
1) Startup latency polish
   - Add an optional warmup on daemon start (open model once) to amortize pipeline compilation. Keep it fast and opt-out by default.
   - Acceptance: “hello” streams within ~2s after daemon start on 20B after the initial warmup.

2) Packaging/rpath cleanup
   - Ensure Harmony dylib install_name uses `@rpath` and relies on `@executable_path/../lib`. Adjust installer with `install_name_tool`.
   - Acceptance: `otool -L codexpcd` shows `@rpath/libopenai_harmony.dylib`.

3) Log hygiene
   - Reduce info logs to: `harmony append …`, `stream start …`, `first delta …`. Gate extra sampling logs behind a build flag.
   - Acceptance: default logs are concise; deep-dive logs available in a debug build.

4) Seed warning cleanup
   - Convert `var seed` → `let seed` in `MetalRunner`.

5) Codex integration tests
   - Update/enable macOS ignored test to assert final-only deltas via XPC. Document checkpoint config path.

6) Optional: memory guardrails
   - Consider dynamic batch sizing based on device memory + model dims.

## Validation Matrix
- Health: CLI `--health` returns ok.
- First request after daemon start: logs show model open → sample rc/out → first delta.
- Second request: no upload latency; immediate deltas.
- Final-only: CLI shows user-facing final text, no commentary.

## Risks & Mitigations
- First-run cost: large models compile kernels and upload weights. Mitigate via warmup and engine cache reuse.
- Harmony drift: decoder fallback ensures text even if parser encounters unexpected streams; keep scaffold updated.
- Memory: fixed batch clamp at 32 by default; revisit for dynamic sizing.

## Where Things Live
- Daemon: `daemon-swift/` (XPC server, engine bridge, Harmony integration)
- Engine bridge: `daemon-swift/Sources/codexpcEngine/`
- Harmony FFI shim: `daemon-swift/Sources/OpenAIHarmony/`
- Core streaming: `daemon-swift/Sources/codexpcCore/MetalRunner.swift`, `SessionManager.swift`, `Harmony*`
- Installer/LaunchAgent: `packaging/`
- Codex provider: `../codex/codex-rs` (XPC in `codexpc-xpc`, client JSON builder in `core/src/client.rs`)

## Quick Troubleshooting
- Only `[created]`, no deltas:
  - Check unified log for `sample rc=… out=…` and `first delta …`. If none, confirm metallib is embedded: `otool -l codexpcd | rg '__METAL|__shaders'`.
  - If sampling ok but no text, look for `decoder fallback` (should switch to raw decode automatically). If absent, verify Harmony dylib is resolvable (`otool -L codexpcd`).
- Immediate `[completed]` with no text:
  - Ensure final-only gating didn’t stop on analysis. The scaffold should steer a final message; if still missing, adjust scaffold wording.
- High memory:
  - Batch clamp is 32 by default; consider lowering for low-RAM devices.

## Ownership & Handoff Notes
- Primary areas: `codexpcCore/*`, `codexpcEngine`, `OpenAIHarmony`, `packaging/`, and Codex `codexpc-xpc` + `core/src/client.rs`.
- Coordination: open issues/PRs in Harmony/GPT‑OSS if C API surfaces or metal build flags need tweaks.

---

## Milestones
- M1: XPC-only final output working on 20B with no runtime envs.
- M2: Codex provider emits correct Harmony JSON; macOS integration smoke passes locally.
- M3: Packaging/rpath polished; optional warmup; concise default logs; docs updated.
