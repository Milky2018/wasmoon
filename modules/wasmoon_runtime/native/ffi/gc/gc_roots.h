#ifndef WASMOON_GC_ROOTS_H
#define WASMOON_GC_ROOTS_H

#include "../context/jit_context.h"
#include "gc_heap.h"

// GC heap management
void ctx_set_gc_heap_internal(jit_context_t *ctx, GcHeap *heap);
void ctx_update_gc_heap_ptr_internal(jit_context_t *ctx);
int32_t ctx_gc_begin_frame_internal(jit_context_t *ctx, uintptr_t frame_id);
void ctx_gc_end_frame_internal(jit_context_t *ctx);
int32_t ctx_gc_push_root_scope_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
);
void ctx_gc_pop_root_scope_internal(jit_context_t *ctx);
void ctx_gc_restore_root_scopes_internal(
    jit_context_t *ctx,
    wasmoon_gc_root_scope_t *marker
);
void ctx_gc_clear_root_scopes_internal(jit_context_t *ctx);
uint32_t gc_safepoint_owner_size(int32_t count);
void ctx_gc_set_safepoint_table_internal(
    jit_context_t *ctx,
    const wasmoon_gc_safepoint_table_t *table
);
int32_t ctx_gc_set_func_safepoints_internal(
    jit_context_t *ctx,
    int32_t func_idx,
    const uint8_t *stackmap_blob,
    int32_t stackmap_blob_size,
    const int32_t *code_offsets,
    int32_t safepoint_count
);
void ctx_gc_use_func_safepoints_internal(
    jit_context_t *ctx,
    int32_t func_idx
);
int32_t ctx_gc_set_root_scratch_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
);
int32_t gc_collect_for_alloc_indexed_internal(
    jit_context_t *ctx, const int64_t *roots, int32_t root_count,
    const uint8_t *indices, int collection_kind,
    const GcTypeLayout *operand_layout, int operand_array
);
int32_t gc_collect_for_alloc_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
);

// Count or copy precise function-frame and explicit-scope roots.
int32_t jit_copy_root_scopes(const jit_execution_state_t *state, int64_t *destination, int32_t capacity);
void WASMOON_GUEST_ABI gc_function_frame_enter_impl(jit_context_t *ctx, wasmoon_gc_function_frame_t *frame,
    const int64_t *roots, const uint64_t *mask, int32_t slot_count);
void WASMOON_GUEST_ABI gc_function_frame_leave_impl(jit_context_t *ctx, wasmoon_gc_function_frame_t *frame);

#endif
