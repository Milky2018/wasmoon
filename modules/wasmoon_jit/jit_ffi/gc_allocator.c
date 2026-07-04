// Copyright 2026
// GC allocation retry helpers (V8-style control flow)

#include "gc_allocator.h"
#include "jit_internal.h"

static void gc_alloc_result_init(gc_alloc_result_t *result) {
    if (!result) {
        return;
    }
    result->gc_ref = 0;
    result->retry_count = 0;
    result->collected_objects = 0;
}

static int32_t collect_and_retry(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
) {
    int32_t collected = gc_collect_for_alloc_internal(ctx, roots, root_count);
    if (collected < 0) {
        return -1;
    }
    if (result) {
        result->retry_count++;
        result->collected_objects += collected;
    }
    return collected;
}

int32_t gc_alloc_struct_with_retry(
    jit_context_t *ctx,
    GcHeap *heap,
    int32_t type_idx,
    const int64_t *fields,
    int32_t num_fields,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
) {
    gc_alloc_result_init(result);
    if (!heap) {
        return 0;
    }

    int32_t gc_ref = gc_heap_alloc_struct(heap, type_idx, fields, num_fields);
    if (gc_ref != 0) {
        if (result) {
            result->gc_ref = gc_ref;
        }
        return gc_ref;
    }

    for (int i = 0; i < 2; i++) {
        if (collect_and_retry(ctx, roots, root_count, result) < 0) {
            return 0;
        }
        gc_ref = gc_heap_alloc_struct(heap, type_idx, fields, num_fields);
        if (gc_ref != 0) {
            if (result) {
                result->gc_ref = gc_ref;
            }
            return gc_ref;
        }
    }

    if (collect_and_retry(ctx, roots, root_count, result) < 0) {
        return 0;
    }
    gc_ref = gc_heap_alloc_struct(heap, type_idx, fields, num_fields);
    if (gc_ref != 0 && result) {
        result->gc_ref = gc_ref;
    }
    return gc_ref;
}

int32_t gc_alloc_array_with_retry(
    jit_context_t *ctx,
    GcHeap *heap,
    int32_t type_idx,
    int32_t len,
    int64_t init_value,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
) {
    gc_alloc_result_init(result);
    if (!heap) {
        return 0;
    }

    int32_t gc_ref = gc_heap_alloc_array(heap, type_idx, len, init_value);
    if (gc_ref != 0) {
        if (result) {
            result->gc_ref = gc_ref;
        }
        return gc_ref;
    }

    for (int i = 0; i < 2; i++) {
        if (collect_and_retry(ctx, roots, root_count, result) < 0) {
            return 0;
        }
        gc_ref = gc_heap_alloc_array(heap, type_idx, len, init_value);
        if (gc_ref != 0) {
            if (result) {
                result->gc_ref = gc_ref;
            }
            return gc_ref;
        }
    }

    if (collect_and_retry(ctx, roots, root_count, result) < 0) {
        return 0;
    }
    gc_ref = gc_heap_alloc_array(heap, type_idx, len, init_value);
    if (gc_ref != 0 && result) {
        result->gc_ref = gc_ref;
    }
    return gc_ref;
}

int32_t gc_alloc_array_from_values_with_retry(
    jit_context_t *ctx,
    GcHeap *heap,
    int32_t type_idx,
    const int64_t *values,
    int32_t len,
    const int64_t *roots,
    int32_t root_count,
    gc_alloc_result_t *result
) {
    gc_alloc_result_init(result);
    if (!heap) {
        return 0;
    }

    int32_t gc_ref = gc_heap_alloc_array_from_values(heap, type_idx, values, len);
    if (gc_ref != 0) {
        if (result) {
            result->gc_ref = gc_ref;
        }
        return gc_ref;
    }

    for (int i = 0; i < 2; i++) {
        if (collect_and_retry(ctx, roots, root_count, result) < 0) {
            return 0;
        }
        gc_ref = gc_heap_alloc_array_from_values(heap, type_idx, values, len);
        if (gc_ref != 0) {
            if (result) {
                result->gc_ref = gc_ref;
            }
            return gc_ref;
        }
    }

    if (collect_and_retry(ctx, roots, root_count, result) < 0) {
        return 0;
    }
    gc_ref = gc_heap_alloc_array_from_values(heap, type_idx, values, len);
    if (gc_ref != 0 && result) {
        result->gc_ref = gc_ref;
    }
    return gc_ref;
}
