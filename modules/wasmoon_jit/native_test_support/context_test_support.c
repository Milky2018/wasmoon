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

MOONBIT_FFI_EXPORT int32_t wasmoon_test_safepoint_ownership(void) {
    jit_context_t *ctx = alloc_context_internal(3);
    if (!ctx) return 0;
    uint8_t blob[] = {1, 2, 3};
    int32_t offsets[] = {4, 12};
    int passed = !ctx_runtime(ctx)->gc_func_safepoint_tables;
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, blob, 3, offsets, 2);
    wasmoon_gc_safepoint_table_t *table = &ctx_runtime(ctx)->gc_func_safepoint_tables[1];
    blob[0] = 9;
    offsets[0] = 20;
    passed &= table->stackmap_blob[0] == 1 && table->code_offsets[0] == 4;
    ctx_gc_use_func_safepoints_internal(ctx, 1);
    passed &= ctx_runtime(ctx)->gc_safepoint_table == table;
    // Replacing one slot must release its previous copies and preserve peers.
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 2, blob, 3, offsets, 2);
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, blob, 1, offsets, 1);
    passed &= table->stackmap_blob_size == 1 && table->code_offsets[0] == 20;
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, NULL, 0, NULL, 0);
    passed &= !table->stackmap_blob && !table->code_offsets;
    ctx_gc_use_func_safepoints_internal(ctx, 1);
    passed &= !ctx_runtime(ctx)->gc_safepoint_table;
    passed &= ctx_runtime(ctx)->gc_func_safepoint_tables[2].stackmap_blob[0] == 9;
    passed &= ctx_gc_set_func_safepoints_internal(ctx, 1, blob, 3, offsets, 2);
    free_context_internal(ctx);
    return passed;
}

extern int64_t wasmoon_jit_context_ptr(void *context);

MOONBIT_FFI_EXPORT int32_t wasmoon_test_callable_lookup(void *view, int64_t value) {
    jit_context_owner_t owner = {0};
    owner.runtime.callable_registry = view;
    return callable_type_for_value(&owner.abi, value);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_callable_lookup(void *context, int64_t value) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return callable_type_for_value(ctx, value);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_callable_subtype(void *context, int64_t value, int32_t expected) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return gc_ref_test_impl(ctx, FUNCREF_TAG | value, expected, 0);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_context_callable_tag(void *context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return ctx_runtime(ctx)->callable_tag_count ? ctx_runtime(ctx)->callable_tags[0] : -1;
}
