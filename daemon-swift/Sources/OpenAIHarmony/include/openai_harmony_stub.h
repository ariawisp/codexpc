#pragma once
#include <stdint.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HarmonyEncodingHandle { int _stub; } HarmonyEncodingHandle;
typedef struct HarmonyStreamableParserHandle { int _stub; } HarmonyStreamableParserHandle;

typedef enum HarmonyStatus {
    HARMONY_STATUS_OK = 0,
    HARMONY_STATUS_INVALID_ARGUMENT = 1,
    HARMONY_STATUS_INTERNAL_ERROR = 2,
} HarmonyStatus;

typedef struct HarmonyOwnedU32Array {
    uint32_t* data;
    size_t len;
} HarmonyOwnedU32Array;

static inline void harmony_string_free(char* s) { (void)s; }

static inline HarmonyStatus harmony_encoding_new(const char* /*name*/, HarmonyEncodingHandle** out_handle, char** out_error) {
    if (!out_handle) return HARMONY_STATUS_INVALID_ARGUMENT;
    *out_handle = (HarmonyEncodingHandle*)0x1; // non-null stub
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline void harmony_encoding_free(HarmonyEncodingHandle* /*enc*/) { }

static inline HarmonyStatus harmony_encoding_render_conversation_for_completion(
    HarmonyEncodingHandle* /*enc*/, const char* /*conversation_json*/, const char* /*next_role*/, const char* /*opts_json*/, HarmonyOwnedU32Array* out_tokens, char** out_error) {
    if (!out_tokens) return HARMONY_STATUS_INVALID_ARGUMENT;
    out_tokens->data = NULL; out_tokens->len = 0;
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline void harmony_owned_u32_array_free(HarmonyOwnedU32Array /*arr*/) { }

static inline HarmonyStatus harmony_encoding_stop_tokens_for_assistant_actions(HarmonyEncodingHandle* /*enc*/, HarmonyOwnedU32Array* out_tokens, char** out_error) {
    if (!out_tokens) return HARMONY_STATUS_INVALID_ARGUMENT;
    out_tokens->data = NULL; out_tokens->len = 0;
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline HarmonyStatus harmony_streamable_parser_new(HarmonyEncodingHandle* /*enc*/, const char* /*role*/, HarmonyStreamableParserHandle** out_parser, char** out_error) {
    if (!out_parser) return HARMONY_STATUS_INVALID_ARGUMENT;
    *out_parser = (HarmonyStreamableParserHandle*)0x1;
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline void harmony_streamable_parser_free(HarmonyStreamableParserHandle* /*p*/) { }

static inline HarmonyStatus harmony_streamable_parser_process(HarmonyStreamableParserHandle* /*p*/, uint32_t /*token*/, char** out_error) {
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline HarmonyStatus harmony_streamable_parser_current_channel(const HarmonyStreamableParserHandle* /*p*/, char** out_str, char** out_error) {
    if (!out_str) return HARMONY_STATUS_INVALID_ARGUMENT;
    *out_str = NULL; // treat as non-final by default
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline HarmonyStatus harmony_streamable_parser_current_recipient(const HarmonyStreamableParserHandle* /*p*/, char** out_str, char** out_error) {
    if (!out_str) return HARMONY_STATUS_INVALID_ARGUMENT;
    *out_str = NULL;
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

static inline HarmonyStatus harmony_streamable_parser_last_content_delta(const HarmonyStreamableParserHandle* /*p*/, char** out_str, char** out_error) {
    if (!out_str) return HARMONY_STATUS_INVALID_ARGUMENT;
    *out_str = NULL; // no delta
    if (out_error) *out_error = NULL;
    return HARMONY_STATUS_OK;
}

#ifdef __cplusplus
}
#endif
