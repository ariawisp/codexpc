# Token Pipeline Unification Plan (codexpc ↔ codex-rs)

This document is a step-by-step implementation plan to migrate Codex (codex-rs) and the macOS XPC daemon (codexpc) to a token-first pipeline built on Harmony. It is written for a Codex CLI agent to take over and implement in phases.

Sibling repositories referenced by relative path from this repo (codexpc):

- codex (Codex CLI and core): `../codex/`
- gpt-oss (engine): `../gpt-oss/`
- harmony (encoder/decoder + C API): `../harmony/`

## Goals

- Remove stringly/JSON conversation formatting in hot paths.
- Render prefill with Harmony once; avoid duplicate/invalid headers.
- Stream via Harmony’s incremental deltas; enforce final-only deltas by default.
- Maintain a safe fallback path during rollout (typed messages).
- Improve TTFB, reduce stalls/duplicates, and simplify debugging.

## Current State (as of this plan)

- codexpc (daemon-swift)
  - Atomic render+prime available via Harmony C API.
  - Parser emits incremental final deltas; call_id included for tools.
  - Barrier before `completed` guarantees ordering against deltas.
  - JSON conversation accepted; strict Harmony parsing enabled.

- codex-rs
  - Provider for macOS XPC (`core/src/codexpc.rs`) builds Harmony conversation via serde_json (no opportunistic string concatenation).
  - Tool events mapped with `call_id` parity.

## Target Architecture

1) Typed messages over XPC (Phase 1)
   - codex-rs builds a typed message array; daemon renders with Harmony C API helper `harmony_encoding_render_conversation_from_messages_ex` + prime.

2) Tokens over XPC (Phase 2)
   - codex-rs renders prefill tokens using Harmony Rust crate and sends `prefill_tokens: [u32]` with a `prime_final` flag to daemon.
   - Daemon appends tokens, primes parser, and streams.

3) Unified streaming semantics
   - Incremental, exactly-once deltas (final channel by default).
   - Tool calls via Harmony parser events, including `call_id`.

## Phased Implementation

### Phase 1: Typed Messages over XPC (fallback path)

Objective: Add a typed (non-JSON) XPC `create_from_messages` to eliminate JSON fragility and to trial Harmony’s message array path.

Changes (codexpc — this repo)

- File: `daemon-swift/Sources/codexpcCore/XpcServer.swift`
  - Add handler for new request type: `create_from_messages`.
  - Input arguments expected on XPC dictionary:
    - `messages`: XPC array of dictionaries with keys:
      - `role`: string ("system" | "user" | "assistant" | "developer" | "tool")
      - `recipient`: string (optional)
      - `channel`: string (optional)
      - `content`: XPC array of content items, each a dictionary:
        - `type`: string ("text" | "image")
        - `text`: string (for type==text)
        - `image_url`: string (for type==image)
    - `tools_json`: string (optional; same schema as current path)
    - `options`: dictionary (optional):
      - `final_only_deltas`: bool (default true)
      - `guarded_stop`: bool (default true)
      - `force_next_channel_final`: bool (default true)

- File: `daemon-swift/Sources/codexpcCore/HarmonyFormatter.swift`
  - Add a method to render from typed messages using Harmony C API:
    - `harmony_encoding_render_conversation_from_messages_ex(...)`
  - Signature (Swift):
    - `func appendMessages(to engine: codexpc_engine_t, messages: [HarmonyMessage], toolsJson: String?, primeParser: OpaquePointer?) throws -> Int`
  - Build and free a C `HarmonyMessageArray` bridging structure.

- File: `daemon-swift/Sources/codexpcCore/SessionManager.swift`
  - Parse the XPC `messages` array when request type is `create_from_messages` and call `appendMessages(..., primeParser: harmonyDecoder.rawParser)`.
  - Preserve existing streaming, barrier, and tool handling.

Changes (codex-rs — `../codex/`)

- File: `codex-rs/codexpc-xpc/src/codexpc_xpc.m`
  - Add a helper function `codexpc_xpc_start_from_messages(...)` mirroring `codexpc_xpc_start` but building `messages` as an XPC array of dictionaries instead of `harmony_conversation`.
  - Wire callback handling unchanged (deltas, completed, tool events).

- File: `codex-rs/codexpc-xpc/src/lib.rs`
  - Add Rust FFI to the new ObjC function; new `stream_from_messages(...)` returning `(Handle, mpsc::UnboundedReceiver<Event>)`.

- File: `codex-rs/core/src/codexpc.rs`
  - Behind a feature flag (e.g., `codexpc_messages_xpc`), convert the current serde_json conversation to a typed message Vec and call `stream_from_messages`.
  - Keep the JSON path as fallback while validating typed path.

Acceptance Criteria

- `codex-cli` streams without JSON parse errors on macOS.
- Tool calls (call_id parity) still work via typed path.
- No regressions in ordering/delta duplication.

### Phase 2: Tokens over XPC (token-first path)

Objective: codex-rs renders prefill tokens via Harmony Rust and sends tokens to daemon, eliminating cross-process JSON/message rendering.

Changes (harmony — `../harmony/`)

- Ensure Harmony Rust crate is consumable by codex-rs (published crate or path dep).
- Expose a stable API for:
  - `load_harmony_encoding(HarmonyGptOss)`
  - `render_conversation_for_completion(&Conversation, Role::Assistant, config)`
  - `stop_tokens_for_assistant_actions()`

Changes (codex-rs — `../codex/`)

- Add a cargo feature (e.g., `codexpc_token_xpc`).
- Add dependency on Harmony Rust crate (git or path to `../harmony`).
- Build `Conversation` + `Message` objects in Rust and obtain `prefill_tokens: Vec<u32>`.
- Implement `stream_from_tokens(...)`:
  - Handshake (optional at first): request daemon’s `encoding_name`, `special_tokens`.
  - Send XPC message `create_from_tokens` with fields:
    - `prefill_tokens` as XPC data (bytes; u32 LE) or array of u64 casted from u32.
    - `prime_final`: bool (true by default).
    - `stop_tokens`: optional array (daemon may compute if omitted).

Changes (codexpc — this repo)

- File: `daemon-swift/Sources/codexpcCore/XpcServer.swift`
  - Add handler for new request type: `create_from_tokens`.
  - Validate and decode `prefill_tokens` to `[UInt32]` (bytes or array path) and append to engine.
  - If `prime_final==true`, call `harmony_streamable_parser_prime_assistant_final` on the decoder parser handle.
  - Optionally compute/accept stop tokens and set them in sampler.

- File: `daemon-swift/Sources/codexpcCore/MetalRunner.swift`
  - Add helper to append tokens directly (already available via `codexpc_engine_append_tokens`).
  - Ensure stream loop is unchanged.

Acceptance Criteria

- `codex-cli` with `codexpc_token_xpc` feature shows equal or better TTFB and smooth streaming.
- Fallback to Phase 1 (typed) remains available behind a feature flag.

### Phase 3: Stream and Tool Parity Hardening

- Keep `output_text.delta` as the user-visible event; optionally add `output_token_ids.delta` behind a feature flag for diagnostics.
- Confirm Harmony deltas are exactly-once (C API uses one-shot `take_last_content_delta`).
- Tool events carry `call_id`; tool outputs appended as Harmony tool messages (tokens path).

### Phase 4: Observability & Backpressure

- Add a lightweight handshake XPC call:
  - Returns: `harmony_semver`, `git_commit`, `encoding_name`, `vocab_hash`, `special_tokens` map.
- Add per-stream metrics (daemon logs + optional counters): `ttfb_ms`, `tokens_per_sec`, `delta_count`, `tool_calls`.
- Bound XPC queue sizes; if client backpressure, coalesce deltas (already done via `StreamEmitter`).

### Phase 5: Config, Flags, and Migration

- codex-rs config keys:
  - `-c provider.codexpc.transport=json|messages|tokens`
  - `-c provider.codexpc.token_stream_debug=true|false`
  - Defaults: `messages` → `tokens` once stable.
- Maintain JSON fallback until tokens path is proven with tooling/apps.

## File-by-File Work Items

codexpc (this repo)

- `daemon-swift/Sources/codexpcCore/XpcServer.swift`
  - [ ] Add handlers for `create_from_messages`, `create_from_tokens`, `handshake`.

- `daemon-swift/Sources/codexpcCore/HarmonyFormatter.swift`
  - [ ] Add `appendMessages(to:messages:toolsJson:primeParser:)` using `harmony_encoding_render_conversation_from_messages_ex`.

- `daemon-swift/Sources/codexpcCore/SessionManager.swift`
  - [ ] Route based on `type`: `create_from_messages` and `create_from_tokens` requests (existing `create` path unchanged).
  - [ ] For tokens path: append prefill tokens, prime parser if requested, then stream.

- `daemon-swift/Sources/codexpcCore/MetalRunner.swift`
  - [ ] Add `appendTokens(_:)` convenience that wraps `codexpc_engine_append_tokens`.

codex-rs (`../codex/`)

- `codex-rs/codexpc-xpc/src/codexpc_xpc.m`
  - [ ] Add `codexpc_xpc_start_from_messages(...)` (XPC dictionary builder for typed messages).
  - [ ] Add `codexpc_xpc_start_from_tokens(...)` that passes raw token bytes + flags.

- `codex-rs/codexpc-xpc/src/lib.rs`
  - [ ] Expose safe Rust wrappers: `stream_from_messages(...)`, `stream_from_tokens(...)`.

- `codex-rs/core/src/codexpc.rs`
  - [ ] Build typed messages in Rust and call `stream_from_messages(...)` (Phase 1).
  - [ ] Add Harmony Rust dependency to compute `prefill_tokens` and call `stream_from_tokens(...)` (Phase 2, behind feature flag).

harmony (`../harmony/`)

- [ ] (Optional) Publish Harmony Rust crate (or set path dep for codex-rs to `../harmony`).
- [ ] Ensure public Rust API exposes encoding render + stop tokens for codex-rs.

## Testing Strategy

- Unit tests (daemon): message→token render with header correctness; parser priming sanity (assistant/final).
- Integration tests:
  - Phase 1: typed messages XPC → stream deltas; tool call smoke.
  - Phase 2: tokens XPC → stream deltas; verify `ttfb_ms` improvement.
- Regression: ensure `completed` ordering correct; no duplicate deltas in logs/UI.
- Performance: record `ttfb_ms`, tokens/sec on the same prompt with JSON vs typed vs tokens paths.

## Rollout & Fallback

- Default to Phase 1 (typed) initially; Phase 2 (tokens) behind feature flag.
- Maintain JSON path during rollout; deprecate once tokens are stable for all supported prompts/tools.

## Risks & Mitigations

- Encoding mismatch (vocab/special tokens):
  - Mitigation: handshake; fallback to typed path.

- Incorrect header rendering or priming drift:
  - Mitigation: atomic render+prime; golden tests; logs capturing role/channel immediately after first token.

- Backpressure and dropped deltas:
  - Mitigation: coalescing emitter (existing), queue bounds, and XPC barrier before `completed`.

## Milestones & Acceptance Checklist

- [ ] Phase 1 implemented (typed messages):
  - [ ] XPC supports `create_from_messages`.
  - [ ] codex-rs uses typed path (flag), no JSON parse errors.
  - [ ] Tool parity holds (call_id present), ordering stable.

- [ ] Phase 2 implemented (tokens):
  - [ ] codex-rs renders prefill tokens via Harmony Rust.
  - [ ] XPC supports `create_from_tokens` + priming.
  - [ ] Measurable TTFB improvement; steady streaming.

- [ ] Observability/backpressure hardening completed.

- [ ] Defaults switched to tokens; JSON deprecated/removed where safe.

