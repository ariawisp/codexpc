#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct codexpc_engine* codexpc_engine_t;

// Opens a GPT‑OSS model from `checkpoint_path` and returns an engine handle.
int codexpc_engine_open(const char* checkpoint_path, codexpc_engine_t* out_engine);

// Resets internal context (clears cached tokens and KV cache).
int codexpc_engine_reset(codexpc_engine_t engine);

// Appends token IDs.
int codexpc_engine_append_tokens(codexpc_engine_t engine, const uint32_t* tokens, size_t num_tokens);

// Appends UTF-8 text (tokenized internally).
int codexpc_engine_append_chars(codexpc_engine_t engine, const char* text, size_t text_len, size_t* out_num_tokens);

// Samples up to `max_tokens`. Writes tokens to `out_tokens` and the count to `out_num_tokens`.
int codexpc_engine_sample(codexpc_engine_t engine, float temperature, uint64_t seed,
                          size_t max_tokens, uint32_t* out_tokens, size_t* out_num_tokens);

// Decodes a token ID into bytes copied into `out_buf`.
// If out_buf_size is too small, returns -2 and writes required size to out_required_size.
int codexpc_engine_decode_token(codexpc_engine_t engine, uint32_t token_id,
                                void* out_buf, size_t out_buf_size, size_t* out_required_size);

// Retrieves the special END token id (if available). Returns 0 on success.
int codexpc_engine_get_end_token_id(codexpc_engine_t engine, uint32_t* out_token_id);

// Retrieves any special token id by numeric token_type matching gptoss_special_token enum.
int codexpc_engine_get_special_token_id(codexpc_engine_t engine, int token_type, uint32_t* out_token_id);

// Releases the engine and underlying resources.
void codexpc_engine_close(codexpc_engine_t engine);

// --- Multi-agent / Shared-KV API ---

// Opaque shared KV arena handle
typedef struct codexpc_shared_kv* codexpc_shared_kv_t;
// Opaque agent stream handle
typedef struct codexpc_agent* codexpc_agent_t;

// Creates a shared KV arena with capacity for `capacity_tokens` tokens. Returns 0 on success.
int codexpc_engine_shared_kv_open(codexpc_engine_t engine, int capacity_tokens, codexpc_shared_kv_t* out_shared);
// Extended: specify slots (agents) and layout (0=CONTIGUOUS, 1=INTERLEAVED)
int codexpc_engine_shared_kv_open_ex(codexpc_engine_t engine, int capacity_tokens, int slots, int layout, codexpc_shared_kv_t* out_shared);

// Destroys a shared KV arena.
void codexpc_engine_shared_kv_close(codexpc_shared_kv_t shared);

// Opens an agent stream bound to a shared KV arena.
int codexpc_engine_agent_open(codexpc_engine_t engine, codexpc_shared_kv_t shared, codexpc_agent_t* out_agent);
// Extended: specify explicit slot assignment (0..slots-1)
int codexpc_engine_agent_open_ex(codexpc_engine_t engine, codexpc_shared_kv_t shared, int slot_index, codexpc_agent_t* out_agent);

// Closes an agent stream.
void codexpc_engine_agent_close(codexpc_agent_t agent);

// Resets an agent stream (clears tokens/pos).
int codexpc_engine_agent_reset(codexpc_agent_t agent);

// Append token IDs to an agent stream.
int codexpc_engine_agent_append_tokens(codexpc_agent_t agent, const uint32_t* tokens, size_t num_tokens);

// Append UTF-8 text to an agent stream (tokenized via Harmony in-engine).
int codexpc_engine_agent_append_chars(codexpc_agent_t agent, const char* text, size_t text_len, size_t* out_num_tokens);

// Indicates whether the next position is a structural boundary (enables <|agent_turn|>/<|collab_bus|> when true).
int codexpc_engine_agent_set_boundary(codexpc_agent_t agent, int at_boundary);

// Sets a logit mask for an agent stream. If `allowed` is non-null, only IDs in `allowed` are permitted;
// `banned` IDs are always suppressed.
int codexpc_engine_agent_set_logit_mask(codexpc_agent_t agent, const int32_t* allowed, size_t allowed_len, const int32_t* banned, size_t banned_len);

// Clears any previously set logit masks.
int codexpc_engine_agent_clear_logit_mask(codexpc_agent_t agent);

// Samples up to `max_tokens` for an agent stream; writes tokens into out_tokens.
int codexpc_engine_agent_sample(codexpc_agent_t agent, float temperature, uint64_t seed, size_t max_tokens,
                                uint32_t* out_tokens, size_t* out_num_tokens);

#ifdef __cplusplus
}
#endif
// Returns the engine version string length into out_required_size.
// If out_buf is non-null and large enough, writes the version string (UTF-8, no trailing NUL required) and returns 0.
int codexpc_engine_get_version(char* out_buf, size_t out_buf_size, size_t* out_required_size);
