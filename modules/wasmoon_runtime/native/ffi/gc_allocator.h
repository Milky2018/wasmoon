// Copyright 2026
#ifndef GC_ALLOCATOR_H
#define GC_ALLOCATOR_H

#include "jit_ffi.h"
#include "gc_heap.h"

// Physical input layouts, not runtime opcodes. Every buffer is borrowed for the
// synchronous allocation call; none may point into the movable heap payload.
typedef enum {
    GC_ALLOC_STRUCT_WORDS,
    GC_ALLOC_ARRAY_WORD,
    GC_ALLOC_ARRAY_WORDS,
    GC_ALLOC_STRUCT_SLOTS,
    GC_ALLOC_ARRAY_SLOT,
    GC_ALLOC_ARRAY_SLOTS
} gc_allocation_layout_t;

typedef struct gc_alloc_result_t {
    int32_t retry_count;
    int32_t collected_objects;
} gc_alloc_result_t;

typedef struct gc_allocation_request_t {
    jit_context_t *ctx;
    GcHeap *heap;
    gc_allocation_layout_t layout;
    int32_t type_idx;
    const void *values;
    int32_t count;
    GcSlot init;
    const int64_t *roots;
    int32_t root_count;
    // Optional borrowed little-endian indices into roots. Only collection
    // materializes these operands; successful allocation does not copy them.
    const uint8_t *root_indices;
    gc_alloc_result_t result;
} gc_allocation_request_t;

// Returns a positive object identity or a negative runtime trap code. The
// caller must release its buffers before raising that trap. The callback never
// suspends, raises a native trap, or retains this stack-allocated request.
int32_t gc_allocate(gc_allocation_request_t *request);

#endif
