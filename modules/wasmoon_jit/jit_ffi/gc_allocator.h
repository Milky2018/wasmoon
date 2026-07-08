// Copyright 2026
// GC allocation retry helpers (V8-style slow path skeleton)

#ifndef GC_ALLOCATOR_H
#define GC_ALLOCATOR_H

#include <stdint.h>
#include "jit_ffi.h"
#include "gc_heap.h"

typedef struct gc_alloc_result_t {
    int32_t gc_ref;
    int32_t retry_count;
    int32_t collected_objects;
} gc_alloc_result_t;

int32_t gc_alloc_struct_with_retry(
    jit_context_t *ctx,
    GcHeap *heap,
    int32_t type_idx,
    const int64_t *fields,
    int32_t num_fields,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
);

int32_t gc_alloc_array_with_retry(
    jit_context_t *ctx,
    GcHeap *heap,
    int32_t type_idx,
    int32_t len,
    int64_t init_value,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
);

int32_t gc_alloc_array_from_values_with_retry(
    jit_context_t *ctx,
    GcHeap *heap,
    int32_t type_idx,
    const int64_t *values,
    int32_t len,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
);

#endif // GC_ALLOCATOR_H
