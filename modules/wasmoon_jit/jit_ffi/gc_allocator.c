// Copyright 2026
// Native storage primitives for the synchronous MoonBit allocation policy.
#include "gc_allocator.h"
#include "jit_internal.h"

static void gc_record_runtime_type(jit_context_t *ctx, GcHeap *heap, int32_t ref, int32_t local_type) {
    if (!ctx || !heap || ref <= 0 || ref > heap->object_count) return;
    if (local_type >= 0 && local_type < ctx_runtime(ctx)->callable_local_type_count) {
        heap->runtime_types[ref - 1] = ctx_runtime(ctx)->callable_local_types[local_type];
    }
}

MOONBIT_FFI_EXPORT int32_t wasmoon_gc_allocation_attempt(void *raw_request) {
    gc_allocation_request_t *request = raw_request;
    GcHeap *heap = request->heap;
    int32_t type = request->type_idx;
    int32_t count = request->count;
    int32_t reference = 0;
    switch (request->layout) {
        case GC_ALLOC_STRUCT_WORDS:
            reference = gc_heap_alloc_struct(heap, type, request->values, count);
            break;
        case GC_ALLOC_ARRAY_WORD:
            reference = gc_heap_alloc_array(heap, type, count, request->init.lo);
            break;
        case GC_ALLOC_ARRAY_WORDS:
            reference = gc_heap_alloc_array_from_values(heap, type, request->values, count);
            break;
        case GC_ALLOC_STRUCT_SLOTS:
            reference = gc_heap_alloc_struct_wide(heap, type, request->values, count);
            break;
        case GC_ALLOC_ARRAY_SLOT:
            reference = gc_heap_alloc_array_wide(heap, type, count, request->init);
            break;
        case GC_ALLOC_ARRAY_SLOTS:
            reference = gc_heap_alloc_array_from_slots(heap, type, request->values, count);
            break;
    }
    gc_record_runtime_type(request->ctx, heap, reference, type);
    return reference;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_gc_allocation_collect(void *raw_request) {
    gc_allocation_request_t *request = raw_request;
    int32_t collected = gc_collect_for_alloc_internal(
        request->ctx, request->roots, request->root_count);
    if (collected >= 0) {
        request->result.retry_count++;
        request->result.collected_objects += collected;
    }
    return collected;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_gc_allocation_denial(void *raw_request) {
    gc_allocation_request_t *request = raw_request;
    return request->heap->quota_denied;
}

int32_t gc_allocate(gc_allocation_request_t *request) {
    // Successful physical allocation needs no policy callback. Only failure
    // enters MoonBit to decide whether to collect, retry or report a trap.
    int32_t reference = wasmoon_gc_allocation_attempt(request);
    if (reference > 0) return reference;
    return request->heap->allocation_policy(request,
        request->layout >= GC_ALLOC_STRUCT_SLOTS);
}
