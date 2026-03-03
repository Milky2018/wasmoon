/**
 * GC Heap Implementation
 *
 * This implements a simple bump-pointer allocator with mark-sweep GC.
 * Objects are stored in a contiguous memory region with a separate
 * object table mapping gc_ref to offsets.
 */

#include "gc_heap.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Default sizes
#define DEFAULT_HEAP_CAPACITY (1024 * 1024)  // 1MB
#define DEFAULT_OBJECT_CAPACITY 1024
#define DEFAULT_FREE_CAPACITY 256

// Alignment
#define ALIGN_UP(x, align) (((x) + (align) - 1) & ~((align) - 1))

// Optional runtime verification mode. Set WASMOON_GC_VERIFY=1 to enable.
static int gc_verify_env_cached = -1;

static int gc_is_truthy_env(const char* value) {
    if (!value) {
        return 0;
    }
    return strcmp(value, "1") == 0
        || strcmp(value, "true") == 0
        || strcmp(value, "TRUE") == 0
        || strcmp(value, "yes") == 0
        || strcmp(value, "YES") == 0
        || strcmp(value, "on") == 0
        || strcmp(value, "ON") == 0;
}

static int gc_verify_enabled(void) {
    if (gc_verify_env_cached < 0) {
        const char* value = getenv("WASMOON_GC_VERIFY");
        gc_verify_env_cached = gc_is_truthy_env(value) ? 1 : 0;
    }
    return gc_verify_env_cached;
}

static void gc_heap_maybe_verify(GcHeap* heap, const char* op_name) {
    if (!gc_verify_enabled()) {
        return;
    }
    if (!gc_heap_verify(heap, 1)) {
        fprintf(stderr, "[GC VERIFY] invariant violation after %s\n", op_name);
        abort();
    }
}

// ============ Internal Helpers ============

static int ensure_heap_capacity(GcHeap* heap, size_t needed) {
    if (heap->size + needed <= heap->capacity) {
        return 1;  // Enough space
    }

    // Grow heap
    size_t new_capacity = heap->capacity * 2;
    while (new_capacity < heap->size + needed) {
        new_capacity *= 2;
    }

    uint8_t* new_data = (uint8_t*)realloc(heap->data, new_capacity);
    if (!new_data) {
        return 0;  // Allocation failed
    }

    heap->data = new_data;
    heap->capacity = new_capacity;
    return 1;
}

static int ensure_object_table_capacity(GcHeap* heap) {
    if (heap->object_count < heap->object_capacity) {
        return 1;  // Enough space
    }

    // Grow object table
    int32_t new_capacity = heap->object_capacity * 2;
    int32_t* new_table = (int32_t*)realloc(heap->object_table,
                                            new_capacity * sizeof(int32_t));
    if (!new_table) {
        return 0;  // Allocation failed
    }

    heap->object_table = new_table;
    heap->object_capacity = new_capacity;
    return 1;
}

static GcHeader* get_object_header(GcHeap* heap, int32_t gc_ref) {
    if (gc_ref <= 0 || gc_ref > heap->object_count) {
        return NULL;
    }
    int32_t offset = heap->object_table[gc_ref - 1];
    if (offset < 0) {
        return NULL;  // Object was freed
    }
    return (GcHeader*)(heap->data + offset);
}

static uint8_t* get_object_data(GcHeap* heap, int32_t gc_ref) {
    GcHeader* header = get_object_header(heap, gc_ref);
    if (!header) {
        return NULL;
    }
    return ((uint8_t*)header) + GC_HEADER_SIZE;
}

// ============ Heap Lifecycle ============

GcHeap* gc_heap_new(size_t initial_capacity) {
    if (initial_capacity == 0) {
        initial_capacity = DEFAULT_HEAP_CAPACITY;
    }

    GcHeap* heap = (GcHeap*)malloc(sizeof(GcHeap));
    if (!heap) {
        return NULL;
    }

    heap->data = (uint8_t*)malloc(initial_capacity);
    if (!heap->data) {
        free(heap);
        return NULL;
    }

    heap->object_table = (int32_t*)malloc(DEFAULT_OBJECT_CAPACITY * sizeof(int32_t));
    if (!heap->object_table) {
        free(heap->data);
        free(heap);
        return NULL;
    }

    heap->free_list = (int32_t*)malloc(DEFAULT_FREE_CAPACITY * sizeof(int32_t));
    if (!heap->free_list) {
        free(heap->object_table);
        free(heap->data);
        free(heap);
        return NULL;
    }

    heap->size = 0;
    heap->capacity = initial_capacity;
    heap->object_count = 0;
    heap->object_capacity = DEFAULT_OBJECT_CAPACITY;
    heap->free_count = 0;
    heap->free_capacity = DEFAULT_FREE_CAPACITY;
    heap->total_allocations = 0;
    heap->total_collections = 0;

    return heap;
}

void gc_heap_free(GcHeap* heap) {
    if (!heap) {
        return;
    }
    free(heap->free_list);
    free(heap->object_table);
    free(heap->data);
    free(heap);
}

// ============ Struct Operations ============

int32_t gc_heap_alloc_struct(GcHeap* heap, int32_t type_idx,
                              const int64_t* fields, int32_t num_fields) {
    if (!heap) {
        return 0;
    }

    // Calculate object size: header + fields
    size_t data_size = num_fields * sizeof(int64_t);
    size_t total_size = ALIGN_UP(GC_HEADER_SIZE + data_size, 16);

    // Ensure capacity
    if (!ensure_heap_capacity(heap, total_size)) {
        return 0;
    }
    if (!ensure_object_table_capacity(heap)) {
        return 0;
    }

    // Allocate object
    int32_t offset = (int32_t)heap->size;
    GcHeader* header = (GcHeader*)(heap->data + offset);

    // Zero entire allocation to avoid uninitialized padding being scanned as refs
    memset(header, 0, total_size);

    header->kind = GC_KIND_STRUCT;
    header->flags = 0;
    header->type_idx = (uint16_t)type_idx;
    header->size = (uint32_t)total_size;
    header->reserved = num_fields;  // Store actual field count for GC

    // Copy field values
    int64_t* field_data = (int64_t*)(heap->data + offset + GC_HEADER_SIZE);
    if (fields && num_fields > 0) {
        memcpy(field_data, fields, num_fields * sizeof(int64_t));
    }

    // Update heap state
    heap->size += total_size;
    int32_t gc_ref = heap->object_count + 1;  // 1-based
    heap->object_table[heap->object_count] = offset;
    heap->object_count++;
    heap->total_allocations++;

    gc_heap_maybe_verify(heap, "alloc_struct");
    return gc_ref;
}

int64_t gc_heap_struct_get(GcHeap* heap, int32_t gc_ref, int32_t field_idx) {
    uint8_t* data = get_object_data(heap, gc_ref);
    if (!data) {
        return 0;  // Invalid reference
    }

    int64_t* fields = (int64_t*)data;
    return fields[field_idx];
}

void gc_heap_struct_set(GcHeap* heap, int32_t gc_ref, int32_t field_idx, int64_t value) {
    uint8_t* data = get_object_data(heap, gc_ref);
    if (!data) {
        return;  // Invalid reference
    }

    int64_t* fields = (int64_t*)data;
    fields[field_idx] = value;
    gc_heap_maybe_verify(heap, "struct_set");
}

// ============ Array Operations ============

int32_t gc_heap_alloc_array(GcHeap* heap, int32_t type_idx,
                             int32_t len, int64_t init_value) {
    if (!heap || len < 0) {
        return 0;
    }

    // Calculate object size: header + length (8 bytes) + elements
    // Array layout: [header][length:i32][padding:i32][elem0:i64][elem1:i64]...
    size_t data_size = 8 + len * sizeof(int64_t);  // 8 = sizeof(int32_t) * 2 for length + padding
    size_t total_size = ALIGN_UP(GC_HEADER_SIZE + data_size, 16);

    // Ensure capacity
    if (!ensure_heap_capacity(heap, total_size)) {
        return 0;
    }
    if (!ensure_object_table_capacity(heap)) {
        return 0;
    }

    // Allocate object
    int32_t offset = (int32_t)heap->size;
    GcHeader* header = (GcHeader*)(heap->data + offset);

    // Zero entire allocation to avoid uninitialized padding being scanned as refs
    memset(header, 0, total_size);

    header->kind = GC_KIND_ARRAY;
    header->flags = 0;
    header->type_idx = (uint16_t)type_idx;
    header->size = (uint32_t)total_size;
    header->reserved = 0;

    // Set array length
    uint8_t* data = heap->data + offset + GC_HEADER_SIZE;
    int32_t* len_ptr = (int32_t*)data;
    len_ptr[0] = len;

    // Initialize elements
    int64_t* elements = (int64_t*)(data + 8);
    for (int32_t i = 0; i < len; i++) {
        elements[i] = init_value;
    }

    // Update heap state
    heap->size += total_size;
    int32_t gc_ref = heap->object_count + 1;  // 1-based
    heap->object_table[heap->object_count] = offset;
    heap->object_count++;
    heap->total_allocations++;

    gc_heap_maybe_verify(heap, "alloc_array");
    return gc_ref;
}

int32_t gc_heap_array_len(GcHeap* heap, int32_t gc_ref) {
    uint8_t* data = get_object_data(heap, gc_ref);
    if (!data) {
        return 0;  // Invalid reference
    }

    int32_t* len_ptr = (int32_t*)data;
    return len_ptr[0];
}

int64_t gc_heap_array_get(GcHeap* heap, int32_t gc_ref, int32_t idx) {
    uint8_t* data = get_object_data(heap, gc_ref);
    if (!data) {
        return 0;  // Invalid reference
    }

    int32_t len = ((int32_t*)data)[0];
    if (idx < 0 || idx >= len) {
        return 0;  // Out of bounds
    }

    int64_t* elements = (int64_t*)(data + 8);
    return elements[idx];
}

void gc_heap_array_set(GcHeap* heap, int32_t gc_ref, int32_t idx, int64_t value) {
    uint8_t* data = get_object_data(heap, gc_ref);
    if (!data) {
        return;  // Invalid reference
    }

    int32_t len = ((int32_t*)data)[0];
    if (idx < 0 || idx >= len) {
        return;  // Out of bounds
    }

    int64_t* elements = (int64_t*)(data + 8);
    elements[idx] = value;
    gc_heap_maybe_verify(heap, "array_set");
}

void gc_heap_array_fill(GcHeap* heap, int32_t gc_ref, int32_t offset,
                        int64_t value, int32_t count) {
    uint8_t* data = get_object_data(heap, gc_ref);
    if (!data) {
        return;
    }

    int32_t len = ((int32_t*)data)[0];
    int64_t* elements = (int64_t*)(data + 8);

    for (int32_t i = 0; i < count && (offset + i) < len; i++) {
        elements[offset + i] = value;
    }
    gc_heap_maybe_verify(heap, "array_fill");
}

void gc_heap_array_copy(GcHeap* heap, int32_t dst_ref, int32_t dst_offset,
                        int32_t src_ref, int32_t src_offset, int32_t count) {
    uint8_t* dst_data = get_object_data(heap, dst_ref);
    uint8_t* src_data = get_object_data(heap, src_ref);
    if (!dst_data || !src_data) {
        return;
    }

    int32_t dst_len = ((int32_t*)dst_data)[0];
    int32_t src_len = ((int32_t*)src_data)[0];
    int64_t* dst_elements = (int64_t*)(dst_data + 8);
    int64_t* src_elements = (int64_t*)(src_data + 8);

    // Bounds check
    if (dst_offset < 0 || src_offset < 0 ||
        dst_offset + count > dst_len || src_offset + count > src_len) {
        return;
    }

    // Use memmove to handle overlapping regions
    memmove(&dst_elements[dst_offset], &src_elements[src_offset],
            count * sizeof(int64_t));
    gc_heap_maybe_verify(heap, "array_copy");
}

int32_t gc_heap_alloc_array_from_values(GcHeap* heap, int32_t type_idx,
                                         const int64_t* values, int32_t len) {
    if (!heap || len < 0) {
        return 0;
    }

    // Calculate object size: header + length (8 bytes) + elements
    size_t data_size = 8 + len * sizeof(int64_t);
    size_t total_size = ALIGN_UP(GC_HEADER_SIZE + data_size, 16);

    // Ensure capacity
    if (!ensure_heap_capacity(heap, total_size)) {
        return 0;
    }
    if (!ensure_object_table_capacity(heap)) {
        return 0;
    }

    // Allocate object
    int32_t offset = (int32_t)heap->size;
    GcHeader* header = (GcHeader*)(heap->data + offset);

    // Zero entire allocation to avoid uninitialized padding being scanned as refs
    memset(header, 0, total_size);

    header->kind = GC_KIND_ARRAY;
    header->flags = 0;
    header->type_idx = (uint16_t)type_idx;
    header->size = (uint32_t)total_size;
    header->reserved = 0;

    // Set array length
    uint8_t* data = heap->data + offset + GC_HEADER_SIZE;
    int32_t* len_ptr = (int32_t*)data;
    len_ptr[0] = len;

    // Copy element values
    int64_t* elements = (int64_t*)(data + 8);
    if (values && len > 0) {
        memcpy(elements, values, len * sizeof(int64_t));
    }

    // Update heap state
    heap->size += total_size;
    int32_t gc_ref = heap->object_count + 1;  // 1-based
    heap->object_table[heap->object_count] = offset;
    heap->object_count++;
    heap->total_allocations++;

    gc_heap_maybe_verify(heap, "alloc_array_from_values");
    return gc_ref;
}

// ============ Type Information ============

int32_t gc_heap_get_type_idx(GcHeap* heap, int32_t gc_ref) {
    GcHeader* header = get_object_header(heap, gc_ref);
    if (!header) {
        return -1;
    }
    return header->type_idx;
}

int32_t gc_heap_get_kind(GcHeap* heap, int32_t gc_ref) {
    GcHeader* header = get_object_header(heap, gc_ref);
    if (!header) {
        return GC_KIND_FREE;
    }
    return header->kind;
}

int32_t gc_heap_is_valid(GcHeap* heap, int32_t gc_ref) {
    if (!heap || gc_ref <= 0 || gc_ref > heap->object_count) {
        return 0;
    }
    int32_t offset = heap->object_table[gc_ref - 1];
    return offset >= 0 ? 1 : 0;
}

// ============ GC Operations ============

void gc_heap_mark(GcHeap* heap, int32_t gc_ref) {
    GcHeader* header = get_object_header(heap, gc_ref);
    if (!header || (header->flags & GC_FLAG_MARKED)) {
        return;  // Already marked or invalid
    }

    header->flags |= GC_FLAG_MARKED;

    // Recursively mark referenced objects
    uint8_t* data = ((uint8_t*)header) + GC_HEADER_SIZE;

    if (header->kind == GC_KIND_STRUCT) {
        // Struct: scan all fields for references
        // Use stored field count (in reserved) to avoid scanning padding bytes
        int32_t num_fields = (int32_t)header->reserved;
        int64_t* fields = (int64_t*)data;

        for (int32_t i = 0; i < num_fields; i++) {
            int64_t value = fields[i];
            // Check if value is a GC reference (even, non-zero)
            // Encoding: gc_ref << 1, so decode with >> 1
            if (value > 0 && (value & 1) == 0) {
                int32_t ref_gc_ref = (int32_t)(value >> 1);
                gc_heap_mark(heap, ref_gc_ref);
            }
        }
    } else if (header->kind == GC_KIND_ARRAY) {
        // Array: scan all elements for references
        int32_t len = ((int32_t*)data)[0];
        int64_t* elements = (int64_t*)(data + 8);

        for (int32_t i = 0; i < len; i++) {
            int64_t value = elements[i];
            // Check if value is a GC reference (even, non-zero)
            if (value > 0 && (value & 1) == 0) {
                int32_t ref_gc_ref = (int32_t)(value >> 1);
                gc_heap_mark(heap, ref_gc_ref);
            }
        }
    }
}

void gc_heap_mark_roots(GcHeap* heap, const int64_t* roots, int32_t num_roots) {
    if (!heap || !roots) {
        return;
    }

    for (int32_t i = 0; i < num_roots; i++) {
        int64_t value = roots[i];
        // Check if value is a GC reference (even, non-zero)
        // Encoding: gc_ref << 1, so decode with >> 1
        if (value > 0 && (value & 1) == 0) {
            gc_heap_mark(heap, (int32_t)(value >> 1));
        }
    }
}

int32_t gc_heap_sweep(GcHeap* heap) {
    if (!heap) {
        return 0;
    }

    int32_t collected = 0;

    for (int32_t i = 0; i < heap->object_count; i++) {
        int32_t offset = heap->object_table[i];
        if (offset < 0) {
            continue;  // Already freed
        }

        GcHeader* header = (GcHeader*)(heap->data + offset);
        if (header->flags & GC_FLAG_MARKED) {
            // Object is reachable, clear mark for next cycle
            header->flags &= ~GC_FLAG_MARKED;
        } else {
            // Object is unreachable, mark as freed
            header->kind = GC_KIND_FREE;
            heap->object_table[i] = -1;  // Mark as freed in table
            collected++;

            // Add to free list (for potential compaction later)
            if (heap->free_count < heap->free_capacity) {
                heap->free_list[heap->free_count++] = i + 1;  // Store gc_ref
            }
        }
    }

    return collected;
}

void gc_heap_compact(GcHeap* heap) {
    if (!heap || heap->object_count == 0) {
        return;
    }

    size_t new_offset = 0;

    for (int32_t i = 0; i < heap->object_count; i++) {
        int32_t old_offset = heap->object_table[i];
        if (old_offset < 0) {
            continue;  // Object was freed, skip
        }

        GcHeader* header = (GcHeader*)(heap->data + old_offset);
        uint32_t obj_size = header->size;

        // Move object to compact position if needed
        if ((size_t)old_offset != new_offset) {
            memmove(heap->data + new_offset, heap->data + old_offset, obj_size);
            heap->object_table[i] = (int32_t)new_offset;
        }

        new_offset += ALIGN_UP(obj_size, 16);
    }

    // Shrink heap size
    heap->size = new_offset;

    // Clear free list (no more free slots after compaction)
    heap->free_count = 0;
}

int32_t gc_heap_collect(GcHeap* heap, const int64_t* roots, int32_t num_roots) {
    if (!heap) {
        return 0;
    }

    // Mark phase
    gc_heap_mark_roots(heap, roots, num_roots);

    // Sweep phase
    int32_t collected = gc_heap_sweep(heap);

    // Compact phase - move surviving objects to eliminate fragmentation
    gc_heap_compact(heap);

    heap->total_collections++;
    gc_heap_maybe_verify(heap, "collect");
    return collected;
}

static int gc_verify_fail(const char* message, int32_t verbose) {
    if (verbose) {
        fprintf(stderr, "[GC VERIFY] %s\n", message);
    }
    return 0;
}

int32_t gc_heap_verify(GcHeap* heap, int32_t verbose) {
    if (!heap) {
        return gc_verify_fail("heap is NULL", verbose);
    }
    if (!heap->data || !heap->object_table || !heap->free_list) {
        return gc_verify_fail("heap buffers are NULL", verbose);
    }
    if (heap->size > heap->capacity) {
        return gc_verify_fail("heap size exceeds capacity", verbose);
    }
    if (heap->object_count < 0 || heap->object_count > heap->object_capacity) {
        return gc_verify_fail("object_count out of bounds", verbose);
    }
    if (heap->free_count < 0 || heap->free_count > heap->free_capacity) {
        return gc_verify_fail("free_count out of bounds", verbose);
    }
    if (heap->total_allocations < 0 || heap->total_collections < 0) {
        return gc_verify_fail("negative GC statistics", verbose);
    }

    size_t previous_end = 0;
    int32_t saw_active = 0;
    for (int32_t i = 0; i < heap->object_count; i++) {
        int32_t gc_ref = i + 1;
        int32_t offset = heap->object_table[i];
        if (offset < 0) {
            continue;
        }

        if ((size_t)offset + GC_HEADER_SIZE > heap->size) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] header out of heap: gc_ref=%d offset=%d size=%zu\n", gc_ref, offset, heap->size);
            }
            return 0;
        }
        if ((offset % 16) != 0) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] unaligned object offset: gc_ref=%d offset=%d\n", gc_ref, offset);
            }
            return 0;
        }

        GcHeader* header = (GcHeader*)(heap->data + offset);
        if (header->size < GC_HEADER_SIZE) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] invalid object size: gc_ref=%d size=%u\n", gc_ref, header->size);
            }
            return 0;
        }
        if ((header->size % 16) != 0) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] object size is not 16-byte aligned: gc_ref=%d size=%u\n", gc_ref, header->size);
            }
            return 0;
        }

        size_t object_end = (size_t)offset + (size_t)header->size;
        if (object_end > heap->size) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] object exceeds heap size: gc_ref=%d end=%zu heap_size=%zu\n", gc_ref, object_end, heap->size);
            }
            return 0;
        }
        if (saw_active && (size_t)offset < previous_end) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] object overlap/order violation: gc_ref=%d offset=%d previous_end=%zu\n", gc_ref, offset, previous_end);
            }
            return 0;
        }
        previous_end = object_end;
        saw_active = 1;

        if (header->kind != GC_KIND_STRUCT && header->kind != GC_KIND_ARRAY) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] invalid active object kind: gc_ref=%d kind=%u\n", gc_ref, header->kind);
            }
            return 0;
        }

        uint8_t* data = ((uint8_t*)header) + GC_HEADER_SIZE;
        size_t payload_size = (size_t)header->size - GC_HEADER_SIZE;

        if (header->kind == GC_KIND_STRUCT) {
            uint64_t num_fields_u64 = header->reserved;
            if (num_fields_u64 > (payload_size / sizeof(int64_t))) {
                if (verbose) {
                    fprintf(stderr, "[GC VERIFY] struct field count exceeds payload: gc_ref=%d fields=%llu payload=%zu\n",
                            gc_ref, (unsigned long long)num_fields_u64, payload_size);
                }
                return 0;
            }
            int64_t* fields = (int64_t*)data;
            int32_t num_fields = (int32_t)num_fields_u64;
            (void)fields;
            (void)num_fields;
        } else {
            if (payload_size < 8) {
                if (verbose) {
                    fprintf(stderr, "[GC VERIFY] array payload too small: gc_ref=%d payload=%zu\n", gc_ref, payload_size);
                }
                return 0;
            }
            int32_t len = ((int32_t*)data)[0];
            if (len < 0) {
                if (verbose) {
                    fprintf(stderr, "[GC VERIFY] negative array length: gc_ref=%d len=%d\n", gc_ref, len);
                }
                return 0;
            }
            size_t need = 8 + ((size_t)len * sizeof(int64_t));
            if (need > payload_size) {
                if (verbose) {
                    fprintf(stderr, "[GC VERIFY] array elements exceed payload: gc_ref=%d len=%d need=%zu payload=%zu\n",
                            gc_ref, len, need, payload_size);
                }
                return 0;
            }
            int64_t* elements = (int64_t*)(data + 8);
            (void)elements;
        }
    }

    for (int32_t i = 0; i < heap->free_count; i++) {
        int32_t gc_ref = heap->free_list[i];
        if (gc_ref <= 0 || gc_ref > heap->object_count) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] free list gc_ref out of range: index=%d gc_ref=%d object_count=%d\n", i, gc_ref, heap->object_count);
            }
            return 0;
        }
        if (heap->object_table[gc_ref - 1] >= 0) {
            if (verbose) {
                fprintf(stderr, "[GC VERIFY] free list entry points to live object: index=%d gc_ref=%d\n", i, gc_ref);
            }
            return 0;
        }
    }

    return 1;
}

// ============ Utilities ============

uint8_t* gc_heap_get_base(GcHeap* heap) {
    return heap ? heap->data : NULL;
}

int32_t gc_heap_get_offset(GcHeap* heap, int32_t gc_ref) {
    if (!heap || gc_ref <= 0 || gc_ref > heap->object_count) {
        return -1;
    }
    return heap->object_table[gc_ref - 1];
}

size_t gc_heap_get_size(GcHeap* heap) {
    return heap ? heap->size : 0;
}

size_t gc_heap_get_capacity(GcHeap* heap) {
    return heap ? heap->capacity : 0;
}

int32_t gc_heap_get_object_count(GcHeap* heap) {
    return heap ? heap->object_count : 0;
}

void gc_heap_get_stats(GcHeap* heap, int32_t* out_total_allocations, int32_t* out_total_collections) {
    if (!heap) {
        if (out_total_allocations) *out_total_allocations = 0;
        if (out_total_collections) *out_total_collections = 0;
        return;
    }
    if (out_total_allocations) *out_total_allocations = heap->total_allocations;
    if (out_total_collections) *out_total_collections = heap->total_collections;
}

// ============ FFI Exports for MoonBit ============

// These functions are exported for MoonBit FFI

int64_t wasmoon_gc_heap_new(int64_t capacity) {
    GcHeap* heap = gc_heap_new((size_t)capacity);
    return (int64_t)(uintptr_t)heap;
}

void wasmoon_gc_heap_free(int64_t heap_ptr) {
    gc_heap_free((GcHeap*)(uintptr_t)heap_ptr);
}

int32_t wasmoon_gc_heap_alloc_struct(int64_t heap_ptr, int32_t type_idx,
                                      int64_t* fields, int32_t num_fields) {
    return gc_heap_alloc_struct((GcHeap*)(uintptr_t)heap_ptr, type_idx, fields, num_fields);
}

int64_t wasmoon_gc_heap_struct_get(int64_t heap_ptr, int32_t gc_ref, int32_t field_idx) {
    return gc_heap_struct_get((GcHeap*)(uintptr_t)heap_ptr, gc_ref, field_idx);
}

void wasmoon_gc_heap_struct_set(int64_t heap_ptr, int32_t gc_ref, int32_t field_idx, int64_t value) {
    gc_heap_struct_set((GcHeap*)(uintptr_t)heap_ptr, gc_ref, field_idx, value);
}

int32_t wasmoon_gc_heap_alloc_array(int64_t heap_ptr, int32_t type_idx,
                                     int32_t len, int64_t init_value) {
    return gc_heap_alloc_array((GcHeap*)(uintptr_t)heap_ptr, type_idx, len, init_value);
}

int32_t wasmoon_gc_heap_array_len(int64_t heap_ptr, int32_t gc_ref) {
    return gc_heap_array_len((GcHeap*)(uintptr_t)heap_ptr, gc_ref);
}

int64_t wasmoon_gc_heap_array_get(int64_t heap_ptr, int32_t gc_ref, int32_t idx) {
    return gc_heap_array_get((GcHeap*)(uintptr_t)heap_ptr, gc_ref, idx);
}

void wasmoon_gc_heap_array_set(int64_t heap_ptr, int32_t gc_ref, int32_t idx, int64_t value) {
    gc_heap_array_set((GcHeap*)(uintptr_t)heap_ptr, gc_ref, idx, value);
}

void wasmoon_gc_heap_array_fill(int64_t heap_ptr, int32_t gc_ref, int32_t offset,
                                 int64_t value, int32_t count) {
    gc_heap_array_fill((GcHeap*)(uintptr_t)heap_ptr, gc_ref, offset, value, count);
}

void wasmoon_gc_heap_array_copy(int64_t heap_ptr, int32_t dst_ref, int32_t dst_offset,
                                 int32_t src_ref, int32_t src_offset, int32_t count) {
    gc_heap_array_copy((GcHeap*)(uintptr_t)heap_ptr, dst_ref, dst_offset,
                       src_ref, src_offset, count);
}

int32_t wasmoon_gc_heap_get_type_idx(int64_t heap_ptr, int32_t gc_ref) {
    return gc_heap_get_type_idx((GcHeap*)(uintptr_t)heap_ptr, gc_ref);
}

int32_t wasmoon_gc_heap_get_kind(int64_t heap_ptr, int32_t gc_ref) {
    return gc_heap_get_kind((GcHeap*)(uintptr_t)heap_ptr, gc_ref);
}

int32_t wasmoon_gc_heap_is_valid(int64_t heap_ptr, int32_t gc_ref) {
    return gc_heap_is_valid((GcHeap*)(uintptr_t)heap_ptr, gc_ref);
}

int64_t wasmoon_gc_heap_get_base(int64_t heap_ptr) {
    return (int64_t)(uintptr_t)gc_heap_get_base((GcHeap*)(uintptr_t)heap_ptr);
}

int32_t wasmoon_gc_heap_get_offset(int64_t heap_ptr, int32_t gc_ref) {
    return gc_heap_get_offset((GcHeap*)(uintptr_t)heap_ptr, gc_ref);
}

int32_t wasmoon_gc_heap_collect(int64_t heap_ptr, int64_t* roots, int32_t num_roots) {
    return gc_heap_collect((GcHeap*)(uintptr_t)heap_ptr, roots, num_roots);
}

int32_t wasmoon_gc_heap_alloc_array_from_values(int64_t heap_ptr, int32_t type_idx,
                                                  int64_t* values, int32_t len) {
    return gc_heap_alloc_array_from_values((GcHeap*)(uintptr_t)heap_ptr, type_idx, values, len);
}

void wasmoon_gc_heap_mark(int64_t heap_ptr, int32_t gc_ref) {
    gc_heap_mark((GcHeap*)(uintptr_t)heap_ptr, gc_ref);
}

void wasmoon_gc_heap_mark_roots(int64_t heap_ptr, int64_t* roots, int32_t num_roots) {
    gc_heap_mark_roots((GcHeap*)(uintptr_t)heap_ptr, roots, num_roots);
}

int32_t wasmoon_gc_heap_sweep(int64_t heap_ptr) {
    return gc_heap_sweep((GcHeap*)(uintptr_t)heap_ptr);
}

int64_t wasmoon_gc_heap_get_size(int64_t heap_ptr) {
    return (int64_t)gc_heap_get_size((GcHeap*)(uintptr_t)heap_ptr);
}

int64_t wasmoon_gc_heap_get_capacity(int64_t heap_ptr) {
    return (int64_t)gc_heap_get_capacity((GcHeap*)(uintptr_t)heap_ptr);
}

int32_t wasmoon_gc_heap_get_object_count(int64_t heap_ptr) {
    return gc_heap_get_object_count((GcHeap*)(uintptr_t)heap_ptr);
}

int32_t wasmoon_gc_heap_get_total_allocations(int64_t heap_ptr) {
    int32_t allocations = 0;
    gc_heap_get_stats((GcHeap*)(uintptr_t)heap_ptr, &allocations, NULL);
    return allocations;
}

int32_t wasmoon_gc_heap_get_total_collections(int64_t heap_ptr) {
    int32_t collections = 0;
    gc_heap_get_stats((GcHeap*)(uintptr_t)heap_ptr, NULL, &collections);
    return collections;
}

int32_t wasmoon_gc_heap_verify(int64_t heap_ptr, int32_t verbose) {
    return gc_heap_verify((GcHeap*)(uintptr_t)heap_ptr, verbose);
}
