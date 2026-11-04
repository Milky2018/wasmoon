#ifndef WASMOON_GC_ACCESS_H
#define WASMOON_GC_ACCESS_H
// Shared checked accessors for the host API and JIT runtime helpers.
// Fixed-size memcpy preserves unaligned access and aliasing safety while
// allowing scalar accesses to become ordinary machine loads and stores.
#include "gc_heap.h"
#include <string.h>
extern int gc_verify_env_cached;

static inline GcHeader* gc_access_object_header(GcHeap* heap, int32_t gc_ref) {
    if (gc_ref <= 0 || gc_ref > heap->object_count) {
        return NULL;
    }
    int32_t offset = gc_heap_identity_offset(heap, gc_ref);
    if (offset < 0) {
        return NULL;  // Object was freed
    }
    return (GcHeader*)(heap->data + offset);
}

static inline uint8_t* gc_access_object_data(GcHeap* heap, int32_t gc_ref) {
    GcHeader* header = gc_access_object_header(heap, gc_ref);
    if (!header) {
        return NULL;
    }
    return ((uint8_t*)header) + GC_HEADER_SIZE;
}

static inline int32_t gc_access_compact_array_width(const GcTypeLayout *layout) {
    return layout && layout->count == 1 && layout->fields[0].offset == 0 &&
        layout->fields[0].width == layout->size && !layout->fields[0].reference
        ? layout->size : 0;
}

static inline uintptr_t gc_access_array_view(const void *payload, int32_t width) {
    uintptr_t code = width == 1 ? 1 : width == 2 ? 2 : width == 4 ? 3 : width == 8 ? 4 : 0;
    return (uintptr_t)payload | code;
}

static inline GcSlot gc_access_layout_read(const uint8_t *data, const GcFieldLayout *field) {
    GcSlot slot = {0, 0};
    switch (field->width) {
    case 1: memcpy(&slot, data + field->offset, 1); break;
    case 2: memcpy(&slot, data + field->offset, 2); break;
    case 4: memcpy(&slot, data + field->offset, 4); break;
    case 8: memcpy(&slot, data + field->offset, 8); break;
    case 16: memcpy(&slot, data + field->offset, 16); break;
    }
    return slot;
}

static inline void gc_access_layout_write(uint8_t *data, const GcFieldLayout *field, GcSlot value) {
    switch (field->width) {
    // Distinct scalar sources prevent Clang from merging these arms back
    // into a variable-length memcpy call. memcpy still permits unaligned data.
    case 1: { uint8_t v = (uint8_t)value.lo; memcpy(data + field->offset, &v, sizeof(v)); break; }
    case 2: { uint16_t v = (uint16_t)value.lo; memcpy(data + field->offset, &v, sizeof(v)); break; }
    case 4: { uint32_t v = (uint32_t)value.lo; memcpy(data + field->offset, &v, sizeof(v)); break; }
    case 8: { uint64_t v = (uint64_t)value.lo; memcpy(data + field->offset, &v, sizeof(v)); break; }
    case 16: memcpy(data + field->offset, &value, 16); break;
    }
}

static inline void gc_access_verify(GcHeap *heap, const char *name) {
    // -1 still initializes the existing environment-controlled verifier.
    if (gc_verify_env_cached != 0) gc_heap_maybe_verify(heap, name);
}

static inline void gc_access_fill_elements(uint8_t *data, int32_t width, GcSlot value, int32_t count) {
    if (!count) return;
    const uint8_t *pattern = (const uint8_t *)&value;
    int repeated_byte = 1;
    for (int32_t i = 1; i < width; i++) {
        if (pattern[i] != pattern[0]) { repeated_byte = 0; break; }
    }
    if (repeated_byte) {
        memset(data, pattern[0], (size_t)count * width);
        return;
    }
    size_t bytes = (size_t)count * width;
    if (bytes < 16) {
        // Sub-vector fills do not amortize building a complete block.
        switch (width) {
        case 2:
            for (int32_t i = 0; i < count; i++) memcpy(data + (size_t)i * 2, &value, 2);
            break;
        case 4:
            for (int32_t i = 0; i < count; i++) memcpy(data + (size_t)i * 4, &value, 4);
            break;
        case 8:
            memcpy(data, &value, 8);
            break;
        }
        return;
    }
    // Widths divide 16. Build one complete pattern and copy fixed-size blocks;
    // this exposes vector stores without alignment assumptions or target SIMD.
    uint8_t block[16];
    memcpy(block, pattern, 16);
    switch (width) {
    case 2:
        memcpy(block + 2, block, 2);
        /* fall through */
    case 4:
        memcpy(block + 4, block, 4);
        /* fall through */
    case 8:
        memcpy(block + 8, block, 8);
    }
    size_t offset = 0;
    for (; bytes - offset >= 16; offset += 16)
        memcpy(data + offset, block, 16);
    if (offset != bytes) memcpy(data + offset, block, bytes - offset);
}

static inline GcSlot gc_access_struct_get(GcHeap* heap, int32_t gc_ref, int32_t field_idx) {
    GcSlot empty = {0, 0};
    uint8_t* data = gc_access_object_data(heap, gc_ref);
    if (!data) {
        return empty;  // Invalid reference
    }

    GcHeader *header = (GcHeader *)(data - GC_HEADER_SIZE);
    if (field_idx < 0 || (uint32_t)field_idx >= (uint32_t)header->reserved) return empty;
    GcTypeLayout *layout = gc_object_layout(heap, header);
    if (layout) return gc_access_layout_read(data, &layout->fields[field_idx]);
    GcSlot* fields = (GcSlot*)data;
    return fields[field_idx];
}

static inline void gc_access_struct_set(GcHeap* heap, int32_t gc_ref, int32_t field_idx,
                             GcSlot value) {
    uint8_t* data = gc_access_object_data(heap, gc_ref);
    if (!data) {
        return;  // Invalid reference
    }

    GcHeader *header = (GcHeader *)(data - GC_HEADER_SIZE);
    if (field_idx < 0 || (uint32_t)field_idx >= (uint32_t)header->reserved) return;
    GcTypeLayout *layout = gc_object_layout(heap, header);
    if (layout) {
        if (layout->fields[field_idx].reference) gc_heap_write_barrier_at(heap, gc_ref, value.lo, field_idx);
        gc_access_layout_write(data, &layout->fields[field_idx], value);
    } else {
        gc_heap_write_barrier_at(heap, gc_ref, value.lo, field_idx);
        ((GcSlot *)data)[field_idx] = value;
    }
    gc_access_verify(heap, "struct_set");
}

static inline int32_t gc_access_array_len(GcHeap* heap, int32_t gc_ref) {
    uint8_t* data = gc_access_object_data(heap, gc_ref);
    if (!data) {
        return 0;  // Invalid reference
    }

    int32_t* len_ptr = (int32_t*)data;
    return len_ptr[0];
}

static inline GcSlot gc_access_array_get(GcHeap* heap, int32_t gc_ref, int32_t idx) {
    GcSlot empty = {0, 0};
    uint8_t* data = gc_access_object_data(heap, gc_ref);
    if (!data) {
        return empty;  // Invalid reference
    }

    int32_t len = ((int32_t*)data)[0];
    if (idx < 0 || idx >= len) {
        return empty;  // Out of bounds
    }

    GcTypeLayout *layout = gc_object_layout(heap, (GcHeader *)(data - GC_HEADER_SIZE));
    if (layout) return gc_access_layout_read(data + GC_ARRAY_DATA_OFFSET + (size_t)idx * layout->size, &layout->fields[0]);
    return ((GcSlot *)(data + GC_ARRAY_DATA_OFFSET))[idx];
}

static inline void gc_access_array_set(GcHeap* heap, int32_t gc_ref, int32_t idx,
                            GcSlot value) {
    uint8_t* data = gc_access_object_data(heap, gc_ref);
    if (!data) {
        return;  // Invalid reference
    }

    int32_t len = ((int32_t*)data)[0];
    if (idx < 0 || idx >= len) {
        return;  // Out of bounds
    }

    GcTypeLayout *layout = gc_object_layout(heap, (GcHeader *)(data - GC_HEADER_SIZE));
    if (layout) {
        if (layout->fields[0].reference) gc_heap_write_barrier_at(heap, gc_ref, value.lo, idx);
        gc_access_layout_write(data + GC_ARRAY_DATA_OFFSET + (size_t)idx * layout->size, &layout->fields[0], value);
    } else {
        gc_heap_write_barrier_at(heap, gc_ref, value.lo, idx);
        ((GcSlot *)(data + GC_ARRAY_DATA_OFFSET))[idx] = value;
    }
    gc_access_verify(heap, "array_set");
}


#endif
