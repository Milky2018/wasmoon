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

// Scratch roots belong to an invocation, including while it is parked.
MOONBIT_FFI_EXPORT int32_t wasmoon_test_activation_scratch_isolation(void) {
    jit_context_t *ctx = alloc_context_internal(1);
    if (!ctx) return 0;
    jit_trap_activation_t outer, inner;
    jit_trap_activation_init(&outer, ctx);
    jit_trap_activation_push(&outer);
    int64_t first = 16, second = 32;
    int passed = ctx_gc_set_root_scratch_internal(ctx, &first, 1);
    jit_trap_activation_init(&inner, ctx);
    jit_trap_activation_push(&inner);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 0;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &second, 1);
    jit_trap_activation_pop(&inner);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 1 &&
        ctx_execution(ctx)->gc_root_scratch[0] == first;
    jit_trap_activation_detach();
    jit_trap_activation_init(&inner, ctx);
    jit_trap_activation_push(&inner);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 0;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &second, 1);
    jit_trap_activation_abandon(&outer);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 1 &&
        ctx_execution(ctx)->gc_root_scratch[0] == second;
    jit_trap_activation_pop(&inner);
    free_context_internal(ctx);
    return passed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_activation_resume_roots(void) {
    jit_context_t *ctx = alloc_context_internal(1);
    if (!ctx) return 0;
    GcHeap *heap = gc_heap_new(1024);
    ctx_set_gc_heap_internal(ctx, heap);
    int32_t ref = gc_heap_alloc_struct(heap, 0, NULL, 0);
    int64_t root = (int64_t)ref << 1;
    jit_trap_activation_t parked, caller;
    jit_trap_activation_init(&parked, ctx);
    jit_trap_activation_push(&parked);
    ctx->debug_current_func_idx = 17;
    int passed = ref != 0 && ctx_gc_set_root_scratch_internal(ctx, &root, 1);
    jit_trap_activation_detach();
    void *registration = NULL;
    passed &= jit_parked_gc_roots_register(&parked, &registration);
    gc_heap_collect(heap, NULL, 0);
    passed &= gc_heap_is_valid(heap, ref);
    jit_trap_activation_init(&caller, ctx);
    jit_trap_activation_push(&caller);
    ctx->debug_current_func_idx = 23;
    int64_t other = 1;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &other, 1);
    jit_trap_activation_attach(&parked);
    passed &= ctx->debug_current_func_idx == 17;
    passed &= ctx_execution(ctx)->gc_root_scratch[0] == root;
    jit_parked_gc_roots_unregister(registration);
    registration = NULL;
    jit_trap_activation_pop(&parked);
    passed &= ctx->debug_current_func_idx == 23;
    passed &= ctx_execution(ctx)->gc_root_scratch[0] == other;
    jit_trap_activation_pop(&caller);
    gc_heap_collect(heap, NULL, 0);
    passed &= !gc_heap_is_valid(heap, ref);
    // Standalone state is independent and destroyed by context teardown.
    passed &= ctx_runtime(ctx)->execution == NULL;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &other, 1);
    jit_trap_activation_init(&caller, ctx);
    jit_trap_activation_push(&caller);
    passed &= ctx_execution(ctx)->gc_root_scratch_len == 1 &&
        ctx_execution(ctx)->gc_root_scratch[0] == other;
    passed &= ctx_gc_set_root_scratch_internal(ctx, &root, 1);
    jit_trap_activation_pop(&caller);
    passed &= ctx_execution(ctx)->gc_root_scratch[0] == other;
    free_context_internal(ctx);
    moonbit_decref(heap);
    return passed;
}
