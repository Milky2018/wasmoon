#ifndef WASMOON_GC_OPS_H
#define WASMOON_GC_OPS_H

#include "../context/jit_ffi.h"
#include "gc_heap.h"

int64_t WASMOON_GUEST_ABI gc_try_array_impl(jit_context_t *ctx, int32_t type, int32_t len, int64_t init);
int64_t WASMOON_GUEST_ABI gc_try_array_wide_impl(jit_context_t *ctx, int32_t type, int32_t len, const GcSlot *init);
int64_t WASMOON_GUEST_ABI gc_reserve_struct_fast_impl(jit_context_t *ctx, int32_t local_type,
    int32_t count, uint64_t shape, int32_t total_size, int64_t *ticket);

// GC operation implementations
int64_t WASMOON_GUEST_ABI gc_struct_new_impl(int32_t type_idx, int64_t *fields, int32_t num_fields);
int64_t WASMOON_GUEST_ABI gc_struct_get_heap_impl(GcHeap *heap, int64_t ref, int32_t field_idx);
void WASMOON_GUEST_ABI gc_struct_set_heap_impl(GcHeap *heap, int64_t ref, int32_t field_idx, int64_t value);
void* WASMOON_GUEST_ABI gc_array_data_heap_impl(GcHeap *heap, int64_t ref, int32_t width);
void* WASMOON_GUEST_ABI gc_struct_data_impl(jit_context_t *ctx, int64_t ref, int32_t type_idx, uint64_t shape, int32_t fields);
int64_t WASMOON_GUEST_ABI gc_array_get_heap_impl(GcHeap *heap, int64_t ref, int32_t idx);
void WASMOON_GUEST_ABI gc_array_set_heap_impl(GcHeap *heap, int64_t ref, int32_t idx, int64_t value);
int32_t WASMOON_GUEST_ABI gc_array_len_heap_impl(GcHeap *heap, int64_t ref);

int64_t WASMOON_GUEST_ABI gc_struct_get_impl(int64_t ref, int32_t type_idx, int32_t field_idx);
void WASMOON_GUEST_ABI gc_struct_set_impl(int64_t ref, int32_t type_idx, int32_t field_idx, int64_t value);
int64_t WASMOON_GUEST_ABI gc_array_new_impl(int32_t type_idx, int32_t len, int64_t fill);
int64_t WASMOON_GUEST_ABI gc_array_get_impl(int64_t ref, int32_t type_idx, int32_t idx);
void WASMOON_GUEST_ABI gc_array_set_impl(int64_t ref, int32_t type_idx, int32_t idx, int64_t value);
int32_t WASMOON_GUEST_ABI gc_array_len_impl(int64_t ref);
void WASMOON_GUEST_ABI gc_array_fill_impl(int64_t ref, int32_t offset, int64_t value, int32_t count);
void WASMOON_GUEST_ABI gc_array_copy_impl(int64_t dst_ref, int32_t dst_offset,
                        int64_t src_ref, int32_t src_offset, int32_t count);

// Inline allocation support (for JIT fast path)
int64_t WASMOON_GUEST_ABI gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size);
int64_t WASMOON_GUEST_ABI gc_register_array_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size);
int64_t WASMOON_GUEST_ABI gc_alloc_struct_slow(jit_context_t *ctx, int32_t type_idx,
                              int64_t *fields, int32_t num_fields, int32_t safepoint_id, int32_t function_index);
int64_t WASMOON_GUEST_ABI gc_alloc_array_slow(jit_context_t *ctx, int32_t type_idx,
                             int32_t len, int64_t init_value, int32_t safepoint_id, int32_t function_index);
int64_t WASMOON_GUEST_ABI gc_alloc_array_from_values_slow(jit_context_t *ctx, int32_t type_idx,
                                         int64_t *values, int32_t len, int32_t safepoint_id, int32_t function_index);

// v128 aggregate operations. A v128 does not fit a runtime word, so these
// carry it through a caller-owned 16-byte GcSlot buffer passed by address.
void WASMOON_GUEST_ABI gc_struct_get_v128_impl(int64_t ref, int32_t type_idx, int32_t field_idx,
                             int64_t out_ptr);
void WASMOON_GUEST_ABI gc_struct_set_v128_impl(int64_t ref, int32_t type_idx, int32_t field_idx,
                             int64_t value_ptr);
void WASMOON_GUEST_ABI gc_array_get_v128_impl(int64_t ref, int32_t type_idx, int32_t idx,
                            int64_t out_ptr);
void WASMOON_GUEST_ABI gc_array_set_v128_impl(int64_t ref, int32_t type_idx, int32_t idx,
                            int64_t value_ptr);
void WASMOON_GUEST_ABI gc_array_fill_v128_impl(int64_t ref, int32_t offset, int64_t value_ptr,
                             int32_t count);
int64_t WASMOON_GUEST_ABI gc_alloc_struct_wide_slow_impl(int64_t ctx_ptr, int32_t type_idx,
                                        int64_t slots_ptr, int32_t num_fields);
int64_t WASMOON_GUEST_ABI gc_alloc_array_wide_slow_impl(int64_t ctx_ptr, int32_t type_idx,
                                       int32_t len, int64_t init_ptr);
int64_t WASMOON_GUEST_ABI gc_alloc_array_from_slots_slow_impl(int64_t ctx_ptr, int32_t type_idx,
                                             int64_t slots_ptr, int32_t len);

#endif
