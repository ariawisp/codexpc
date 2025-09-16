# CodexPC Handoff Plan (Phased)

This plan captures the remaining work to bring CodexPC (macOS XPC daemon + Codex provider) to a robust, testable state. It is organized in phases with concrete tasks, acceptance criteria, and notes on risks and dependencies.

Scope: codexpc (daemon-swift, packaging, scripts), codex (codex-rs provider path, tests), harmony (consume existing C API only; no upstream changes assumed).

## Current State (Summary)
- Daemon (Swift):
  - XPC server, session lifecycle, streaming via GPT‑OSS + Harmony C API.
  - Harmony conversation render (system + user) and Harmony streamable parser for deltas + tool-call detection.
  - Emits: created, output_text.delta, output_item.done (tool_call/tool_call.output), completed (with token_usage).
  - Demo tool execution behind gates: CODEXPC_ALLOW_TOOLS=1 (+ allowlist via CODEXPC_ALLOWED_TOOLS).
- Codex (Rust):
  - Built-in provider `codexpc` (macOS): direct XPC streaming; CLI fallback on non‑macOS.
  - Builds Harmony conversation JSON, inserts developer message with demo tools, maps daemon events to ResponseEvent.
  - macOS unit tests + an ignored integration test harness (spawns daemon with env hooks).
- Packaging/docs:
  - LaunchAgent install, binary install path (/opt fallback), health CLI flag.

---

## Phase 1 — Developer Message + Tool Schemas (1–2 days)
Tasks
- Build a richer developer message in Codex conversation JSON:
  - Include a concise “how to call tools” blurb (recipient=tool name, JSON arguments in commentary channel).
  - Include per‑tool schema snippets (already present for demo tools); format safely for Harmony.
- Optional: use `harmony_get_tool_namespace_config` (from the Harmony C API) if available to retrieve canonical tool namespace info and embed selectively.

Acceptance
- Developer message appears as the first non‑system message in the conversation JSON when tools are available.
- Model reliably produces tool calls for demo tools in local tests (manual or integration).

Risks/Notes
- Keep message compact to avoid inflating input_tokens. Gate inclusion based on presence of tools.

---

## Phase 2 — Argument Handling + Validation (2–3 days)
Tasks
- Daemon: if `input` is valid JSON, include it as `arguments` in tool_call item (already implemented); normalize or reject invalid structures with a clear error.
- Add minimal schema validation for demo tools (e.g., echo/upper expect `{ msg: string }`).
- Emit `tool_call.output` status `failed` with descriptive `output` on validation failure; `completed` otherwise.

Acceptance
- JSON arguments pass-through is visible in events.
- Invalid JSON arguments return a `failed` tool output with an actionable message.
- Unit tests cover success/failure paths.

Risks/Notes
- Keep validation minimal and safe; do not overfit a schema engine yet.

---

## Phase 3 — Tool Execution Pipeline (Optional/Extensible) (3–5 days)
Tasks
- Finalize the demo ToolExecutor contract (already added): `(output, ok)`; centralize allowlist gates.
- Add timeouts and output size caps. Ensure no blocking on tool execution.
- Structure `tool_call.output` payloads consistently (name, status, output); ensure they map in Codex.

Acceptance
- Deterministic test: forced tool call produces call + output items in order; respects allowlist and timeouts.
- No daemon stalls on slow tools.

Risks/Notes
- Keep tools local and safe. No shell by default; if ever added, wrap with sandboxing and explicit consent.

---

## Phase 4 — Harmony Conversation Expansion (2–4 days)
Tasks
- Codex conversation JSON:
  - Confirm inclusion of image parts (`image_url`) behaves as expected; keep in dev message that images may be present.
  - Ensure roles ordering: system → developer → user/assistant.
- Daemon:
  - Continue rendering via Harmony C API; ensure robust fallback if Harmony unavailable.

Acceptance
- Mixed content prompts (text + image) render and stream without crashes.
- Final‑channel deltas stream; commentary is not surfaced to user.

Risks/Notes
- Harmony C API availability on CI/macOS runners.

---

## Phase 5 — Provider Parity & Event Mapping (2–4 days)
Tasks
- Codex mapping completeness:
  - Ensure `OutputItemDone` covers: CustomToolCall, CustomToolCallOutput (done/failed), and room for FunctionCall if added.
  - Surface `token_usage` consistently; add any missing fields (e.g., cached token counts) when available.
- Cancellation/backpressure:
  - Validate cancel behaviour; confirm quick exit on cancel; document.

Acceptance
- All emitted daemon events map to Codex ResponseEvent and display coherently.
- Manual cancel test stops streaming quickly (<100ms typical).

Risks/Notes
- Codex UI may need small tweaks to display tool outputs distinctly.

---

## Phase 6 — Testing & CI (3–5 days)
Tasks
- Daemon unit tests:
  - HarmonyStreamDecoder: feed synthetic tokens to trigger tool_event; assert only `final` deltas emitted.
  - ToolExecutor: validation and allowlist (already added + extend for error edge cases).
- macOS integration tests (ignored by default):
  - Spawn daemon (via CODEXPCD_BIN), force tool calls via `CODEXPC_TEST_FORCE_TOOL` and assert event order: created → tool_call → (tool_call.output) → completed.
- CI updates:
  - macOS job runs unit tests by default; provide a manual trigger (workflow_dispatch) for integration tests with secrets/paths.

Acceptance
- Unit tests pass on macOS; integration test runs green locally.
- CI reliably runs unit tests; integration tests gated.

Risks/Notes
- Integration tests require a local checkpoint and Harmony lib.

---

## Phase 7 — Packaging & Distribution (2–3 days)
Tasks
- Install script cleanups: better error messages if Harmony/GPT‑OSS envs missing; detect arm64 vs x86_64.
- Codesign/notarize (optional): developer-id signing for local distribution; document steps.
- Brew tap (optional): formula to install the daemon and plist.

Acceptance
- One‑command install/uninstall on macOS; logs and service status documented.

Risks/Notes
- Notarization requires Apple Developer account.

---

## Phase 8 — Observability & Telemetry (1–2 days)
Tasks
- Structured logging: request IDs, tool names, durations, token counts.
- Add basic counters (tokens in/out, tool call count, failures). Keep disabled by default or behind env.

Acceptance
- Logs are actionable for debugging; counters visible via log grep or lightweight export.

Risks/Notes
- Keep PII out of logs; truncate long inputs/outputs.

---

## Phase 9 — Security & Hardening (2–4 days)
Tasks
- Tool sandboxing & resource limits (if any new tools are added): timeouts, memory caps, output size caps.
- XPC input validation: enforce `proto_version`, required fields, and type checks (already doing basic checks).
- Fuzz simple JSON paths (arguments handling) to avoid crashes.

Acceptance
- Fuzz runs do not crash the daemon on malformed messages; invalid tool calls are rejected with `failed` output.

Risks/Notes
- Keep the surface minimal; CodexPC is macOS‑only by design.

---

## Phase 10 — Documentation & Handoff (1–2 days)
Tasks
- Docs:
  - Update codexpc README + quickstart + engine-integration with Harmony C API steps.
  - Update Codex docs/integrations/codexpc.md with provider instructions, env vars, and macOS integration test steps.
- Env vars reference (daemon):
  - `GPTOSS_INCLUDE_DIR`, `GPTOSS_LIB_DIR` — GPT‑OSS headers/libs
  - `HARMONY_INCLUDE_DIR`, `HARMONY_LIB_DIR` — Harmony headers/libs
  - `CODEXPC_ALLOW_TOOLS` (1/0) — enable demo tool execution
  - `CODEXPC_ALLOWED_TOOLS` ("echo,upper") — allowlist of tool names
  - `CODEXPC_TEST_FORCE_TOOL` ("name:input") — force a tool call for tests
- Runbooks:
  - How to run daemon locally, health, streaming smoke.
  - How to run macOS unit tests and integration tests.

Acceptance
- A new engineer can follow docs to build, run, and test locally without prior context.

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

## Verification Checklist (per phase)
- Unit tests pass locally on macOS (daemon + codex core).
- Integration test (ignored) passes with a local checkpoint and daemon binary.
- Manual smoke: Swift CLI `--health`, a short stream, and a forced tool call.

