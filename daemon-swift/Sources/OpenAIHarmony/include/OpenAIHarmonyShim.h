
#ifndef OPENAI_HARMONY_SHIM_H
#define OPENAI_HARMONY_SHIM_H

// Prefer real Harmony header when available; otherwise fall back to local stub.
#if __has_include("openai_harmony.h")
#  include "openai_harmony.h"
#else
#  include "openai_harmony_stub.h"
#endif

#endif
