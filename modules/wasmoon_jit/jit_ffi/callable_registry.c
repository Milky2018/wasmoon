#include "jit_internal.h"

extern int64_t wasmoon_jit_context_ptr(void *context);

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_bind_callable_registry(
    void *managed_context, void *registry,
    const int32_t *local_types, int32_t local_count,
    const int32_t *tags, int32_t tag_count
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(managed_context);
    if (!ctx) return 1;
    if (local_count < 0 || tag_count < 0 ||
        (local_count && !local_types) || (tag_count && !tags)) return 0;
    int32_t *local_copy = local_count ? malloc((size_t)local_count * sizeof(int32_t)) : NULL;
    int32_t *tag_copy = tag_count ? malloc((size_t)tag_count * sizeof(int32_t)) : NULL;
    if ((local_count && !local_copy) || (tag_count && !tag_copy)) {
        free(local_copy);
        free(tag_copy);
        return 0;
    }
    if (local_count) memcpy(local_copy, local_types, (size_t)local_count * sizeof(int32_t));
    if (tag_count) memcpy(tag_copy, tags, (size_t)tag_count * sizeof(int32_t));
    jit_runtime_state_t *state = ctx_runtime(ctx);
    moonbit_incref(registry);
    if (state->callable_registry) moonbit_decref(state->callable_registry);
    free(state->callable_local_types);
    free(state->callable_tags);
    state->callable_registry = registry;
    state->callable_local_types = local_copy;
    state->callable_local_type_count = local_count;
    state->callable_tags = tag_copy;
    state->callable_tag_count = tag_count;
    return 1;
}
