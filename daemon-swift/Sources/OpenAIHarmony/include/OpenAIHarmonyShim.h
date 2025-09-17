
#ifndef OPENAI_HARMONY_SHIM_H
#define OPENAI_HARMONY_SHIM_H

// Require the real Harmony C API. No stub fallback is supported.
#if __has_include("openai_harmony.h")
#include "openai_harmony.h"
#elif __has_include(<openai_harmony.h>)
#include <openai_harmony.h>
#elif __has_include("../../../../../harmony/include/openai_harmony.h")
#include "../../../../../harmony/include/openai_harmony.h"
#else
#error "openai_harmony.h not found. Set HARMONY_INCLUDE_DIR or place header in Sources/OpenAIHarmony/include"
#endif

#endif
