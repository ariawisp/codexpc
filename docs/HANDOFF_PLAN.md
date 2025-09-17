# CodexPC Handoff Plan (Updated)

Scope: codexpc (daemon-swift, packaging, scripts), codex (macOS provider + tests), gpt-oss (Metal C API use), harmony (consume official C API or stub).

This update reflects fixes landed during this pass, the current known-good runbook, and the next steps for a new engineer to take it over the finish line.

## Current State (What Works)
- XPC daemon (Swift) runs as a LaunchAgent, exposes a Mach service, and streams events:
  - Events: `created`, `output_text.delta`, `output_item.done` (tool_call/tool_call.output), `completed` (with token_usage).
  - Tooling: Demo tools behind gates (`CODEXPC_ALLOW_TOOLS=1`, `CODEXPC_ALLOWED_TOOLS`), with per‑call timeout and output caps.
  - Harmony: Formatter + stream decoder integrated; commentary deltas suppressed by default (final‑channel only). No stub fallback; real C API required.
- Codex provider (Rust):
  - macOS XPC path with direct streaming; CLI fallback on non‑macOS.
  - Harmony conversation JSON builder (system → developer → user), with developer message gated on presence of tools.
  - Event mapping covers `CustomToolCall` and `CustomToolCallOutput`; token_usage surfaced.
  - Minor fixes: error mapping cleanup, sender ownership fix, unit tests adjusted.
- Swift unit tests: Tool executor (allowlist, timeout, size cap + invalid JSON paths), emitter, Harmony init; pass with stubs.
- Packaging: Single install script builds GPT‑OSS, wires metallib, installs LaunchAgent.

## Key Improvements This Pass
- macOS XPC bridge fixed (non‑ARC build, tool_call.output plumbed).
- Developer message gated on tools (avoids token bloat when not needed).
- Tool validation/tests added; CLI prints tool call/output for quick smokes.
- GPT‑OSS Metal weight upload made robust for LaunchAgent:
  - Added Private‑storage uploads with chunked blits (env: `GPTOSS_WEIGHTS_PRIVATE=1`).
  - Optional mlock disabled (env: `GPTOSS_DISABLE_MLOCK=1`) to avoid pinning ~13GB and inflating resident memory.
  - Engine reuse in daemon (simple in‑process cache keyed by checkpoint) to avoid re‑uploading weights per request.
- Batch size clamp plumbed (env: `CODEXPC_MAX_BATCH_TOKENS`, forwarded to GPT‑OSS) to reduce activation footprint.

## Known Issues / Open Questions
- LaunchAgent vs interactive: A single giant Shared MTLBuffer wrap failed only under LaunchAgent; Python/interactive C worked. Private storage + blit upload resolves this path. Keep Private upload enabled for LaunchAgent.
- First‑request overhead: Expect one‑time weight uploads and pipeline creation on daemon start. Subsequent requests should not re‑upload (engine cache); confirm with logs.
- Streaming verification with large models: With `GPTOSS_WEIGHTS_PRIVATE=1`, `GPTOSS_DISABLE_MLOCK=1`, and a reasonable `CODEXPC_MAX_BATCH_TOKENS` (e.g., 32), streaming should produce deltas on 20B. If not, validate tokenizer/decoder path and Harmony stub toggles.

## Handoff Checklist (Do This First)
1) Install daemon (no runtime env required):
   - `../packaging/install-agent.sh`
2) Reload agent if needed: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.yourorg.codexpc.plist && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yourorg.codexpc.plist`
3) Verify health: `swift run -c release codexpc-cli --health` → `health: ok`.
4) Verify first load logs: in `~/Library/Logs/com.yourorg.codexpc.err.log` expect:
   - `Warning: using Private storage upload for shared weights (...)`
   - `Warning: using Private storage upload for MoE block #...`
   These should appear once per daemon start, not per request.
5) Stream smoke: `swift run -c release codexpc-cli --checkpoint /path/to/model.bin --prompt "hello" --max-tokens 32` → expect `created`, deltas, `completed`.

## Next Engineer Plan (Prioritized)
1) Stabilize Private weight upload
   - Ensure we never re‑upload on subsequent requests (engine cache hits). Add a log line on cache hit/miss.
   - Cap upload chunk size by device limit (consider querying `maxBufferLength`).
   - No env toggles in the default path; keep behavior fixed.
   Acceptance: first request logs show uploads; second request shows no uploads; deltas stream.

2) Activation memory guardrails
   - Default conservative batch clamp (32) is baked in; consider dynamic sizing in future.
   Acceptance: Activity Monitor shows stable RSS after first request; second request does not grow.

3) Foreground dev mode
   - Add `--foreground` flag or env to run the daemon outside launchd for iterative testing; same envs apply.
   - Document how to run CLI against the foreground daemon.
   Acceptance: foreground run streams tokens with the same envs on first try.

4) Harmony stream decoder
  - Harmony decoding is always on by default. Commentary deltas suppressed.
  - Add a unit test to confirm commentary suppression (final only).

5) Upstream GPT‑OSS PR (optional)
   - Contribute Private‑storage upload + `GPTOSS_DISABLE_MLOCK` guard upstream, behind env flags.

## Env Vars
None required at runtime. Build/link envs may be used for local development only.

## Validation Matrix
- Health: CLI `--health` returns ok.
- First request: logs show Private uploads; memory rises during upload then stabilizes.
- Second request: no upload logs; memory stable; deltas stream.
- Tool path: with tools enabled, see `[tool_call]` then `[tool_call.output]` and `completed`.

## Risks & Notes
- LaunchAgent context is stricter about giant Shared buffers; Private upload sidesteps this reliably.
- Large models still have significant activation memory; batch clamp and KV cache size drive memory.
- Engine cache is process‑local; a daemon restart re‑uploads weights (expected). Consider a future warm‑start option if needed.

## Where Things Live
- Daemon: `daemon-swift/` (XPC server, engine bridge, Harmony integration)
- GPT‑OSS bridge: `daemon-swift/Sources/codexpcEngine/` (env‑driven batch clamp)
- Harmony FFI shim/stub: `daemon-swift/Sources/OpenAIHarmony/`
- Codex provider (macOS): `../codex/codex-rs` (XPC bridge in `codexpc-xpc`, client mapping in `core/src/client.rs`)
- Installer/LaunchAgent: `packaging/`

## Quick Troubleshooting
- No deltas, immediate completed: ensure Harmony linked correctly and decoder not swallowing commentary (decoder is enabled by default). Check logs for engine errors.
- Memory spikes: batch clamp defaults to 32; verify engine cache reuse (no upload logs on second request).
- Metal library not found in smoke: ensure `default.metallib` is copied next to binary by the installer.

---

## Milestones
- M1: Dev message + tool schemas; argument pass-through validated.
- M2: Tool execution pipeline hardened (timeouts/allowlist), structured outputs mapped; unit tests added.
- M3: macOS CI (unit), integration test runnable; packaging refined; docs updated.

## Risks & Mitigations
- Harmony availability on CI: keep unit tests that don’t require Harmony; gate integration tests.
- Model behaviour drift: provide `CODEXPC_TEST_FORCE_TOOL` to keep integration tests deterministic.
- Tool safety: keep demo-only by default; require explicit env gates for execution.

## Ownership & Handoff Notes
- Primary code areas:
  - Daemon Swift: `daemon-swift/Sources/codexpcCore/*`, `codexpcEngine`, `OpenAIHarmony`, packaging scripts.
  - Codex provider: `codex-rs/codexpc-xpc/`, `codex-rs/core/src/client.rs` (provider path + JSON builder), tests under `codex-rs/core/tests`.
- Coordination points:
  - If Harmony C API surface changes are needed, open an issue/PR in the Harmony repo.
  - For new tools, review safety gates and add tests before enabling.

---

## Updated Handoff Focus (Next Engineer)

1) Finalize streaming UX
- Ensure Harmony emits final‑channel deltas for simple prompts. Keep raw decode as a safety fallback but prefer Harmony by default.
- Acceptance: `codexpc-cli --checkpoint <model> --prompt "Hello"` shows visible streaming text without toggles.

2) Add a macOS integration test
- Foreground daemon + short prompt; assert created → non‑empty delta(s) → completed.

3) Observability polish
- Log kernel/metallib source, Harmony init success, first N token ids; keep concise.

4) Docs
- Update README/quickstart to emphasize single‑command install and no runtime env.

## Verification Checklist (per phase)
- Unit tests pass locally on macOS (daemon + codex core).
- Integration test (ignored) passes with a local checkpoint and daemon binary.
- Manual smoke: Swift CLI `--health`, a short stream, and a forced tool call.
