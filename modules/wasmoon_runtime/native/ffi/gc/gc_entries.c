// Copyright 2025
#include "gc_ops.h"
#include "../control/trap.h"
#include "gc_roots.h"
#include "gc_types.h"

// ============ GC Runtime FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_ref_test_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_ref_test_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_ref_cast_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_ref_cast_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_new_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_struct_new_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_get_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_struct_get_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_set_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_struct_set_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_get_v128_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_struct_get_v128_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_set_v128_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_struct_set_v128_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_get_v128_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_get_v128_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_set_v128_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_set_v128_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_fill_v128_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_fill_v128_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_struct_wide_slow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_alloc_struct_wide_slow_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_array_wide_slow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_alloc_array_wide_slow_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_array_from_slots_slow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_alloc_array_from_slots_slow_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_new_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_get_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_get_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_set_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_set_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_len_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_len_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_fill_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_fill_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_copy_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_copy_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_type_check_subtype_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_type_check_subtype_impl);
}

// Inline allocation support (ctx-passing)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_register_struct_inline_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_register_struct_inline);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_register_array_inline_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_register_array_inline);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_struct_slow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_alloc_struct_slow);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_array_slow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_alloc_array_slow);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_array_from_values_slow_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_alloc_array_from_values_slow);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_function_frame_enter_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_function_frame_enter_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_function_frame_leave_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_function_frame_leave_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_reserve_struct_fast_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_reserve_struct_fast_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_try_array_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_try_array_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_try_array_wide_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_try_array_wide_impl);
}

// ============ GC Heap Pointer Management ============

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_clear_heap_managed(void *jit_context) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_set_gc_heap_internal(ctx, NULL);
}

// Host-triggered collection must include the dynamically active guest roots.
// Raw heap collection also retains registered parked continuations.
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_collect_heap(
    GcHeap *heap_ptr,
    int64_t *roots,
    int32_t root_count
) {
    GcHeap *heap = gc_heap_live(heap_ptr);
    jit_context_t *active = get_current_jit_context_fast();
    if (active && ctx_gc_heap(active) == heap) {
        return gc_collect_for_alloc_internal(active, roots, root_count);
    }
    if (!heap->precise_roots) jit_mark_active_gc_roots(heap);
    return gc_heap_collect(heap, roots, root_count);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_environment_is_clear_managed(
    void *jit_context
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx) return 0;
    return ctx_gc_heap(ctx) == NULL &&
        ctx_gc_heap_ptr(ctx) == NULL &&
        ctx_gc_heap_limit(ctx) == NULL &&
        ctx_runtime(ctx)->gc_type_cache == NULL &&
        ctx_runtime(ctx)->gc_canonical_indices == NULL &&
        ctx_runtime(ctx)->gc_func_type_indices == NULL &&
        ctx_runtime(ctx)->gc_func_table == NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_clear_cache_managed(
    void *jit_context
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    clear_type_cache_internal((jit_context_t *)(uintptr_t)ctx_ptr);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_heap_managed(
    void *jit_context, GcHeap *heap_ptr
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    GcHeap *heap = gc_heap_live(heap_ptr);
    ctx_set_gc_heap_internal(ctx, heap);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_begin_frame_managed(
    void *jit_context, int64_t frame_id
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return ctx_gc_begin_frame_internal(ctx, (uintptr_t)frame_id);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_end_frame_managed(void *jit_context) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_end_frame_internal(ctx);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_push_root_scope_managed(
    void *jit_context, int64_t *roots, int32_t root_count
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return ctx_gc_push_root_scope_internal(ctx, roots, root_count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_pop_root_scope_managed(
    void *jit_context
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_pop_root_scope_internal(ctx);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_collect_for_alloc_managed(
    void *jit_context, int64_t *roots, int32_t root_count
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return gc_collect_for_alloc_internal(ctx, roots, root_count);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_set_root_scratch_managed(
    void *jit_context, int64_t *roots, int32_t root_count
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return ctx_gc_set_root_scratch_internal(ctx, roots, root_count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_safepoint_table_managed(
    void *jit_context, int64_t table_ptr
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    const wasmoon_gc_safepoint_table_t *table =
        (const wasmoon_gc_safepoint_table_t *)(uintptr_t)table_ptr;
    ctx_gc_set_safepoint_table_internal(ctx, table);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_use_func_safepoints_managed(
    void *jit_context, int32_t func_idx
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_use_func_safepoints_internal(ctx, func_idx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_get_heap_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_struct_get_heap_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_set_heap_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_struct_set_heap_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_get_heap_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_array_get_heap_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_set_heap_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_array_set_heap_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_len_heap_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_array_len_heap_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_data_heap_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_array_data_heap_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_data_ptr(void) {
 return WASMOON_GUEST_ADDRESS(gc_struct_data_impl);
}
