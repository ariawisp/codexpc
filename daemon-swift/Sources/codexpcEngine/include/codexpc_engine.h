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

#ifdef __cplusplus
}
#endif
