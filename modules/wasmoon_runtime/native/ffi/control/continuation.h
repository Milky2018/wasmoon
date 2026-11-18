#ifndef WASMOON_CONTINUATION_H
#define WASMOON_CONTINUATION_H

#include "../context/jit_context.h"

typedef struct native_continuation_type {
    int32_t index;
    int32_t params;
    int32_t results;
    int64_t trampoline;
    int32_t *roots;
    struct native_continuation_type *next;
} native_continuation_type_t;

typedef struct {
    jit_context_t *context;
    native_continuation_type_t *type;
    int64_t function;
} continuation_create_request_t;

void continuation_arena_release(struct native_continuation_arena *arena);
void continuation_types_free(jit_context_t *ctx);

#endif
