#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int harmony_render_system_tokens(const char* instructions,
                                 uint32_t** out_tokens,
                                 size_t* out_len);

void harmony_tokens_free(uint32_t* tokens, size_t len);

#ifdef __cplusplus
}
#endif
