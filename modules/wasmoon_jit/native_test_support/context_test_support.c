#include "../jit_ffi/jit_internal.h"

extern void wasmoon_jit_ctx_init_data_segments(int64_t ctx, int count);
extern void wasmoon_jit_ctx_init_elem_segments(int64_t ctx, int count);

// Exercise the optional state's ownership through reset, reuse and destruction.
MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_optional_state(void) {
    jit_context_t *first = alloc_context_internal(1);
    jit_context_t *second = alloc_context_internal(1);
    if (!first || !second) {
        free_context_internal(first);
        free_context_internal(second);
        return 0;
    }
    int passed = !ctx_runtime(first)->segments &&
        !ctx_runtime(first)->exception_arena && !ctx_runtime(first)->continuation_arena;
    int64_t address = (int64_t)(uintptr_t)first;
    wasmoon_jit_ctx_init_data_segments(address, 0);
    wasmoon_jit_ctx_init_elem_segments(address, 0);
    passed = passed && !ctx_runtime(first)->segments;
    wasmoon_jit_ctx_init_data_segments(address, 1);
    wasmoon_jit_ctx_init_elem_segments(address, 2);
    passed = passed && ctx_runtime(first)->segments &&
        ctx_runtime(first)->segments->data_segment_count == 1 &&
        ctx_runtime(first)->segments->elem_segment_count == 2 &&
        !ctx_runtime(second)->segments;
    ctx_clear_segments_internal(first);
    passed = passed && !ctx_runtime(first)->segments;
    ctx_clear_segments_internal(first);
    wasmoon_jit_ctx_init_elem_segments(address, 1);
    passed = passed && ctx_runtime(first)->segments &&
        ctx_runtime(first)->segments->elem_segment_count == 1 &&
        !ctx_runtime(first)->segments->data_segments;
    free_context_internal(first);
    free_context_internal(second);
    return passed;
}

extern void *wasmoon_jit_alloc_context_managed(int func_count);
extern int64_t wasmoon_jit_context_ptr(void *context);
extern int32_t wasmoon_jit_bind_callable_registry(void *context, void *registry,
    const int32_t *locals, int32_t local_count, const int32_t *tags, int32_t tag_count);
extern int32_t wasmoon_callable_registry_replace(void *registry,
    const int32_t *parents, int32_t count, const int64_t *entries, int32_t entry_count);
extern void wasmoon_callable_registry_clear(void *registry);

MOONBIT_FFI_EXPORT int32_t wasmoon_test_shared_callable_registry(void *first, void *second) {
    void *owners[3];
    jit_context_t *contexts[3];
    int32_t locals[] = {0, 1};
    int32_t tags[] = {7, 8};
    int32_t parents[] = {-1, 0};
    int64_t entries[] = {0x1000000, 1};
    int passed = wasmoon_callable_registry_replace(first, parents, 2, entries, 1);
    entries[1] = 0;
    passed &= wasmoon_callable_registry_replace(second, parents, 2, entries, 1);
    for (int i = 0; i < 3; ++i) {
        owners[i] = wasmoon_jit_alloc_context_managed(1);
        contexts[i] = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(owners[i]);
        if (!contexts[i]) abort();
        passed &= wasmoon_jit_bind_callable_registry(owners[i], i == 2 ? second : first,
            &locals[i % 2], 1, &tags[i % 2], 1);
    }
    passed &= ctx_runtime(contexts[0])->callable_registry == ctx_runtime(contexts[1])->callable_registry;
    passed &= ctx_runtime(contexts[0])->callable_registry != ctx_runtime(contexts[2])->callable_registry;
    passed &= ctx_runtime(contexts[0])->callable_tags[0] == 7;
    passed &= ctx_runtime(contexts[1])->callable_tags[0] == 8;
    int64_t value = FUNCREF_TAG | 0x1000000;
    passed &= callable_type_for_value(contexts[0], value) == 1;
    passed &= callable_type_for_value(contexts[2], value) == 0;
    passed &= gc_ref_test_impl(contexts[0], value, 0, 0) == 1;
    passed &= gc_ref_test_impl(contexts[1], value, 0, 0) == 1;
    // Updating one Store changes both bound contexts without rebinding locals.
    passed &= wasmoon_callable_registry_replace(first, parents, 2, entries, 1);
    passed &= callable_type_for_value(contexts[0], value) == 0;
    passed &= callable_type_for_value(contexts[1], value) == 0;
    passed &= gc_ref_test_impl(contexts[1], value, 0, 0) == 0;
    passed &= gc_ref_test_impl(contexts[0], value, INT32_MAX, 0) == 0;
    entries[1] = -1;
    passed &= wasmoon_callable_registry_replace(first, parents, 2, entries, 1);
    passed &= gc_ref_test_impl(contexts[0], value, 0, 0) == 0;
    entries[1] = 0;
    passed &= wasmoon_callable_registry_replace(first, parents, 2, entries, 1);
    // Rejected replacement preserves the old view.
    passed &= !wasmoon_callable_registry_replace(first, parents, -1, entries, 1);
    passed &= !wasmoon_callable_registry_replace(first, NULL, 2, entries, 1);
    passed &= callable_type_for_value(contexts[0], value) == 0;
    // Rebinding and releasing a peer must not destroy a surviving shared view.
    passed &= wasmoon_jit_bind_callable_registry(owners[0], second, locals, 1, tags, 1);
    moonbit_decref(owners[2]);
    entries[1] = 1;
    passed &= wasmoon_callable_registry_replace(second, parents, 2, entries, 1);
    passed &= callable_type_for_value(contexts[0], value) == 1;
    passed &= callable_type_for_value(contexts[1], value) == 0;
    wasmoon_callable_registry_clear(first);
    wasmoon_callable_registry_clear(first);
    passed &= callable_type_for_value(contexts[1], value) == -1;
    passed &= callable_type_for_value(contexts[0], value) == 1;
    moonbit_decref(owners[0]);
    moonbit_decref(owners[1]);
    return passed;
}
