#include "../jit_ffi/jit_internal.h"

#include <stdint.h>

MOONBIT_FFI_EXPORT int32_t
wasmoon_test_gc_environment_is_clear(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx) return 0;
    return ctx->gc_heap == NULL &&
        ctx->gc_heap_ptr == NULL &&
        ctx->gc_heap_limit == NULL &&
        ctx->gc_type_cache == NULL &&
        ctx->gc_canonical_indices == NULL &&
        ctx->gc_func_type_indices == NULL &&
        ctx->gc_func_table == NULL;
}
