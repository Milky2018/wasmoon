// Physical GC layouts are immutable and shared by allocation, access and tracing.
#include "gc_heap.h"
#include "gc_access.h"
#include "native_alloc.h"
#include <moonbit.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>


int32_t wasmoon_gc_heap_define_layout(GcHeap *heap, int32_t identity,
                                    const int32_t *codes, int32_t array) {
    int32_t count = Moonbit_array_length(codes);
    if (!heap || identity < 0 || identity == INT32_MAX || (array && count != 1)) return 0;
    GcTypeLayout *existing = gc_heap_layout(heap, identity);
    if (existing) {
        if (existing->kind != (array ? GC_KIND_ARRAY : GC_KIND_STRUCT) || existing->count != count) return 0;
        for (int32_t i = 0; i < count; i++) {
            int32_t code = existing->fields[i].reference == 2 ? -9 : existing->fields[i].reference ? -8 : existing->fields[i].width;
            if (code != codes[i]) return 0;
        }
        return 1;
    }
    if (identity >= heap->layout_capacity) {
        int64_t capacity = heap->layout_capacity ? (int64_t)heap->layout_capacity * 2 : 16;
        if (capacity <= identity) capacity = (int64_t)identity + 1;
        if (capacity > INT32_MAX) return 0;
        GcTypeLayout **layouts = wasmoon_native_realloc(heap->layouts, (size_t)capacity * sizeof(*layouts));
        if (!layouts) return 0;
        memset(layouts + heap->layout_capacity, 0, (size_t)(capacity - heap->layout_capacity) * sizeof(*layouts));
        heap->layouts = layouts;
        heap->layout_capacity = (int32_t)capacity;
    }
    GcTypeLayout *layout = wasmoon_native_calloc(1, sizeof(*layout) + (size_t)count * sizeof(GcFieldLayout));
    if (!layout) return 0;
    layout->kind = array ? GC_KIND_ARRAY : GC_KIND_STRUCT;
    layout->count = count;
    int64_t size = 0;
    for (int32_t i = 0; i < count; i++) {
        int32_t width = (codes[i] == -8 || codes[i] == -9) ? 8 : codes[i];
        if (!(width == 1 || width == 2 || width == 4 || width == 8 || width == 16) ||
            (codes[i] < 0 && codes[i] != -8 && codes[i] != -9)) { free(layout); return 0; }
        size = (size + width - 1) & -(int64_t)width;
        if (size + width > INT32_MAX) { free(layout); return 0; }
        layout->fields[i] = (GcFieldLayout){(int32_t)size, width, codes[i] == -9 ? 2 : codes[i] < 0};
        layout->reference_count += codes[i] < 0;
        if (i < 16) {
            uint64_t code = width == 1 ? 1 : width == 2 ? 2 : width == 4 ? 3 : width == 8 ? 4 : 5;
            if (codes[i] < 0) code |= 8;
            layout->prefix_shape |= code << (i * 4);
        }
        size += width;
    }
    layout->size = (int32_t)size;
    heap->layouts[identity] = layout;
    return 1;
}

GcSlot gc_layout_read(const uint8_t *data, const GcFieldLayout *field) {
    return gc_access_layout_read(data, field);
}

void gc_layout_write(uint8_t *data, const GcFieldLayout *field, GcSlot value) {
    gc_access_layout_write(data, field, value);
}

int32_t gc_heap_alloc_typed(GcHeap *heap, int32_t identity, int32_t local_type,
    int32_t count, const void *values, int wide, int repeated, GcSlot init) {
    GcTypeLayout *layout = gc_heap_layout(heap, identity);
    if (!layout || count < 0 || (layout->kind == GC_KIND_STRUCT && count != layout->count)) return 0;
    heap->quota_denied = 0;
    int array = layout->kind == GC_KIND_ARRAY;
    int64_t bytes = gc_layout_allocation_size(layout, count);
    // The prepared window owns capacity, not identities. Ordinary allocations
    // can consume it without repeated capacity/debug/quota calls. Every other
    // case retains the complete allocator and its failure ordering.
    int prepared = heap->allocation_control && heap->allocation_control->enabled &&
        !heap->byte_reservation && !heap->object_reservation && bytes <= INT32_MAX &&
        heap->size <= (size_t)(INT32_MAX - bytes) &&
        (size_t)bytes <= heap->capacity - heap->size &&
        (!heap->precise_roots || heap->size < heap->collection_limit) &&
        heap->object_count < heap->identity_window_limit;
    if (prepared) {
        heap->allocation_control->attempts++;
    } else {
        if (gc_should_fail_allocation()) return 0;
        if (bytes > INT32_MAX || !gc_heap_admit(heap, (size_t)bytes)) return 0;
        if (!gc_heap_ensure_payload_capacity(heap, (size_t)bytes) || !gc_heap_ensure_object_capacity(heap)) {
            gc_heap_undo_admission(heap);
            return 0;
        }
    }
    int32_t offset = (int32_t)heap->size;
    GcHeader *header = (GcHeader *)(heap->data + offset);
    int repeated_array = array && (repeated || !values);
    size_t body_bytes = array ? (size_t)count * layout->size : 0;
    int fill_array = array && body_bytes >= 16 && (!repeated_array || init.lo || init.hi);
    if (fill_array) {
        // Every element is written below before publication. Only metadata and
        // alignment padding need zeroing; do not write the array body twice.
        size_t end = GC_HEADER_SIZE + GC_ARRAY_DATA_OFFSET + (size_t)count * layout->size;
        memset(header, 0, GC_HEADER_SIZE + GC_ARRAY_DATA_OFFSET);
        if ((size_t)bytes != end)
            memset((uint8_t *)header + end, 0, (size_t)bytes - end);
    } else {
        memset(header, 0, (size_t)bytes);
    }
    header->kind = (uint8_t)layout->kind;
    header->type_idx = (uint16_t)local_type;
    header->size = (uint32_t)bytes;
    header->reserved = ((uint64_t)(identity + 1) << 32) | (array ? 0 : (uint32_t)count);
    uint8_t *data = (uint8_t *)header + GC_HEADER_SIZE;
    if (array) *(int32_t *)data = count;
    // Default zero arrays already have initialized bodies. A v128 with only a
    // nonzero high word still needs the full-width fill.
    if (repeated_array && body_bytes >= 16) {
        if (init.lo || init.hi) {
            gc_access_fill_elements(data + GC_ARRAY_DATA_OFFSET, layout->size, init, count);
        }
    } else if ((!repeated_array && values) || init.lo || init.hi) {
        for (int32_t i = 0; i < count; i++) {
            GcSlot value = init;
            if (!repeated && values) {
                value = wide ? ((const GcSlot *)values)[i] : (GcSlot){((const int64_t *)values)[i], 0};
            }
            gc_layout_write(array ? data + GC_ARRAY_DATA_OFFSET + (size_t)i * layout->size : data,
                &layout->fields[array ? 0 : i], value);
        }
    }
    heap->size += (size_t)bytes;
    if (prepared) return gc_heap_publish_object(heap, offset, identity);
    int32_t ref = gc_heap_register_object(heap, offset);
    gc_heap_set_runtime_type(heap, ref, identity);
    gc_heap_maybe_verify(heap, "alloc_typed");
    return ref;
}

int32_t wasmoon_gc_heap_alloc_typed(GcHeap *heap, int32_t identity, int32_t local_type,
                                   const int64_t *words, int32_t count, int32_t repeated) {
    if (!words || Moonbit_array_length(words) < (repeated ? 2 : (int64_t)count * 2)) return 0;
    GcSlot init = {0, 0};
    if (repeated) memcpy(&init, words, sizeof(init));
    return gc_heap_alloc_typed(heap, identity, local_type, count, words, 1, repeated, init);
}


// Trace epochs are separate from collector marks. Rollback liveness queries
// therefore cannot collect, clear marks, or turn arena payload edges into roots.
static uint32_t next_trace_epoch(GcHeap *heap) {
    if (!heap || !heap->data) return 0;
    if (++heap->trace_epoch == 0) {
        for (int32_t i = 0; i < heap->identity_page_capacity; i++) {
            if (heap->identity_pages[i]) memset(heap->identity_pages[i]->visit_epochs, 0,
                sizeof(heap->identity_pages[i]->visit_epochs));
        }
        heap->trace_epoch = 1;
    }
    return (int32_t)heap->trace_epoch;
}

typedef struct { int64_t *data; int32_t size, capacity; } TraceWords;
static int trace_push(TraceWords *words, int64_t word) {
    if (words->size == words->capacity) {
        if (words->capacity > INT32_MAX / 2) return 0;
        int32_t capacity = words->capacity ? words->capacity * 2 : 32;
        int64_t *data = wasmoon_native_realloc(words->data, (size_t)capacity * sizeof(int64_t));
        if (!data) return 0;
        words->data = data;
        words->capacity = capacity;
    }
    words->data[words->size++] = word;
    return 1;
}

typedef struct { int32_t *data; int32_t size, capacity; } TraceRefs;
typedef struct { GcHeap *heap; uint32_t epoch; TraceRefs objects; int failed; } NativeTrace;
static void free_native_trace(void *opaque) {
    NativeTrace *trace = opaque;
    free(trace->objects.data);
    moonbit_decref(trace->heap);
}

void *wasmoon_gc_heap_begin_trace(GcHeap *heap) {
    NativeTrace *trace = moonbit_make_external_object(free_native_trace, sizeof(*trace));
    memset(trace, 0, sizeof(*trace));
    moonbit_incref(heap);
    trace->heap = heap;
    trace->epoch = next_trace_epoch(heap);
    return trace;
}

int64_t *wasmoon_gc_trace_objects(NativeTrace *trace) {
    int64_t *result = moonbit_make_int64_array(trace->objects.size, 0);
    for (int32_t i = 0; i < trace->objects.size; i++) result[i] = (int64_t)trace->objects.data[i] << 1;
    return result;
}

void wasmoon_gc_trace_mark(NativeTrace *trace) {
    if (trace->failed) return;
    for (int32_t i = 0; i < trace->objects.size; i++) {
        int32_t offset = gc_heap_identity_offset(trace->heap, trace->objects.data[i]);
        if (offset >= 0) {
            gc_heap_mark_header(trace->heap, trace->objects.data[i],
                (GcHeader *)(trace->heap->data + offset));
        }
    }
}

static int trace_object(GcHeap *heap, int32_t ref, uint32_t epoch, TraceRefs *objects) {
    GcIdentityPage *page = gc_heap_identity_page(heap, ref);
    int32_t slot = (ref - 1) & (GC_ID_PAGE_SIZE - 1);
    if (page->visit_epochs[slot] == epoch) return 1;
    if (objects->size == objects->capacity) {
        if (objects->capacity > INT32_MAX / 2) return 0;
        int32_t capacity = objects->capacity ? objects->capacity * 2 : 32;
        int32_t *data = wasmoon_native_realloc(objects->data, (size_t)capacity * sizeof(int32_t));
        if (!data) return 0;
        objects->data = data;
        objects->capacity = capacity;
    }
    objects->data[objects->size++] = ref;
    page->visit_epochs[slot] = epoch;
    return 1;
}

// Output: [0, boundary (word, kind) pairs...]. Typed identities stay in the
// owner, without per-object managed allocation. Untyped edges remain Store work.
// -1 denotes an untyped seed; -2 means the graph could not be completed.
int64_t *wasmoon_gc_heap_trace_graph(NativeTrace *trace, int32_t ref) {
    if (trace->failed) return moonbit_make_int64_array(1, -2);
    GcHeap *heap = trace->heap;
    int32_t offset = gc_heap_identity_offset(heap, ref);
    if (offset < 0 || !gc_object_layout(heap, (GcHeader *)(heap->data + offset)))
        return moonbit_make_int64_array(1, -1);
    TraceRefs *objects = &trace->objects;
    TraceWords boundary = {0};
    int32_t start = objects->size;
    int complete = trace_object(heap, ref, trace->epoch, objects);
    for (int32_t cursor = start; complete && cursor < objects->size; cursor++) {
        int32_t current = objects->data[cursor];
        GcHeader *header = (GcHeader *)(heap->data + gc_heap_identity_offset(heap, current));
        GcTypeLayout *layout = gc_object_layout(heap, header);
        int array = header->kind == GC_KIND_ARRAY;
        const uint8_t *data = (uint8_t *)header + GC_HEADER_SIZE;
        int32_t count = array ? *(const int32_t *)data : layout->count;
        if (layout->reference_count == 0) continue;
        for (int32_t i = 0; complete && i < count; i++) {
            GcFieldLayout *field = &layout->fields[array ? 0 : i];
            if (!field->reference) continue;
            int64_t word = gc_layout_read(array ? data + GC_ARRAY_DATA_OFFSET + (size_t)i * layout->size : data, field).lo;
            if (!word) continue;
            if (field->reference != 2) {
                // i31 is odd, including negative i31. It is not a continuation.
                if ((word & 1) && !(word > 0 && ((uint64_t)word & UINT64_C(0x7000000000000000)) == UINT64_C(0x1000000000000000))) continue;
                const uint64_t tags = UINT64_C(0x7000000000000000);
                uint64_t child64 = (uint64_t)word >> 1;
                if (word > 0 && !((uint64_t)word & tags) && child64 <= INT32_MAX) {
                    int32_t child = (int32_t)child64;
                    int32_t child_offset = gc_heap_identity_offset(heap, child);
                    if (child_offset >= 0 && gc_object_layout(heap, (GcHeader *)(heap->data + child_offset))) {
                        complete = trace_object(heap, child, trace->epoch, objects);
                        continue;
                    }
                }
            }
            complete = trace_push(&boundary, word) && trace_push(&boundary, field->reference);
        }
    }
    int64_t *result;
    if (!complete || boundary.size > ((1 << 27) - 2)) {
        trace->failed = 1;
        result = moonbit_make_int64_array(1, -2);
    } else {
        result = moonbit_make_int64_array(1 + boundary.size, 0);
        if (boundary.size) memcpy(result + 1, boundary.data, (size_t)boundary.size * sizeof(int64_t));
    }
    free(boundary.data);
    return result;
}
