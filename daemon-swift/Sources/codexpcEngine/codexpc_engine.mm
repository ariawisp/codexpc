#import "codexpc_engine.h"
#include <gpt-oss/functions.h>
#include <string.h>

struct codexpc_engine {
    gptoss_model_t model = nullptr;
    gptoss_context_t context = nullptr;
    gptoss_tokenizer_t tokenizer = nullptr;
};

static inline int to_errno(enum gptoss_status s) {
    if (s == gptoss_status_success) return 0;
    return (int)s;
}

int codexpc_engine_open(const char* checkpoint_path, codexpc_engine_t* out_engine) {
    if (!checkpoint_path || !out_engine) return -1;
    *out_engine = nullptr;
    auto* e = new codexpc_engine();
    enum gptoss_status st = gptoss_model_create_from_file(checkpoint_path, &e->model, 0);
    if (st != gptoss_status_success) { delete e; return to_errno(st); }
    st = gptoss_model_get_tokenizer(e->model, &e->tokenizer);
    if (st != gptoss_status_success) { gptoss_model_release(e->model); delete e; return to_errno(st); }
    st = gptoss_context_create(e->model, 0, &e->context);
    if (st != gptoss_status_success) {
        gptoss_tokenizer_release(e->tokenizer);
        gptoss_model_release(e->model);
        delete e; return to_errno(st);
    }
    *out_engine = e;
    return 0;
}

int codexpc_engine_reset(codexpc_engine_t engine) {
    if (!engine) return -1;
    return to_errno(gptoss_context_reset(engine->context));
}

int codexpc_engine_append_tokens(codexpc_engine_t engine, const uint32_t* tokens, size_t num_tokens) {
    if (!engine || (!tokens && num_tokens != 0)) return -1;
    return to_errno(gptoss_context_append_tokens(engine->context, num_tokens, tokens));
}

int codexpc_engine_append_chars(codexpc_engine_t engine, const char* text, size_t text_len, size_t* out_num_tokens) {
    if (!engine || (!text && text_len != 0)) return -1;
    return to_errno(gptoss_context_append_chars(engine->context, text, text_len, out_num_tokens));
}

int codexpc_engine_sample(codexpc_engine_t engine, float temperature, uint64_t seed,
                          size_t max_tokens, uint32_t* out_tokens, size_t* out_num_tokens) {
    if (!engine || !out_tokens || !out_num_tokens) return -1;
    return to_errno(gptoss_context_sample(engine->context, temperature, seed, max_tokens, out_tokens, out_num_tokens));
}

int codexpc_engine_decode_token(codexpc_engine_t engine, uint32_t token_id,
                                void* out_buf, size_t out_buf_size, size_t* out_required_size) {
    if (!engine || !out_required_size) return -1;
    const void* ptr = nullptr; size_t sz = 0;
    enum gptoss_status st = gptoss_tokenizer_decode(engine->tokenizer, token_id, &ptr, &sz);
    if (st != gptoss_status_success) return to_errno(st);
    *out_required_size = sz;
    if (!out_buf || out_buf_size < sz) return -2;
    memcpy(out_buf, ptr, sz);
    return 0;
}

int codexpc_engine_get_end_token_id(codexpc_engine_t engine, uint32_t* out_token_id) {
    if (!engine || !out_token_id) return -1;
    return to_errno(gptoss_tokenizer_get_special_token_id(engine->tokenizer, gptoss_special_token_end, out_token_id));
}

int codexpc_engine_get_special_token_id(codexpc_engine_t engine, int token_type, uint32_t* out_token_id) {
    if (!engine || !out_token_id) return -1;
    if (token_type <= 0 || token_type >= gptoss_special_token_max) return -1;
    return to_errno(gptoss_tokenizer_get_special_token_id(engine->tokenizer, (gptoss_special_token)token_type, out_token_id));
}

void codexpc_engine_close(codexpc_engine_t engine) {
    if (!engine) return;
    if (engine->context) gptoss_context_release(engine->context);
    if (engine->tokenizer) gptoss_tokenizer_release(engine->tokenizer);
    if (engine->model) gptoss_model_release(engine->model);
    delete engine;
}
