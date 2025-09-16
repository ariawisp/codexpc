# codexpc Protocol (v1)

Transport: libxpc dictionaries. All messages include a common envelope:

- proto_version: u16 (1)
- service: string ("codexpc")
- req_id: string (UUID)
- ts_ns: u64 (host monotonic timestamp)
- type: string (message type)

## Client → Daemon

- type: "create"
  - model: string
  - checkpoint_path: string
  - instructions: string
  - input: array<object> (Responses API-like items)
  - tools: array<object>
  - reasoning?: object
  - text?: object
  - sampling?: { temperature?: f32, top_p?: f32 }
  - max_output_tokens?: u32

- type: "cancel"
  - req_id: string

## Daemon → Client (events)

- type: "created"
  - features?: array<string>

- type: "output_text.delta"
  - text: string

- type: "output_item.done"
  - item: object

- type: "completed"
  - response_id: string
  - token_usage?: { input_tokens?: u32, output_tokens?: u32, total_tokens?: u32 }

- type: "error"
  - code: string
  - message: string

## Notes

- Backpressure: daemon coalesces output_text.delta at 15–30ms cadence.
- Cancellation: upon receiving cancel, daemon stops sampling promptly and emits a final completed with partial output.
- Versioning: bump proto_version when adding breaking changes; optional fields should be feature-gated via `features`.

