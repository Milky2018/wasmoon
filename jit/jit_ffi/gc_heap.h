/**
 * GC Heap for WebAssembly GC Types
 *
 * This file implements a unified GC heap that can be used by both
 * the interpreter and JIT-compiled code. All GC objects (structs and arrays)
 * are stored in a contiguous memory region managed by C.
 *
 * Value Encoding (all values stored as int64_t):
 * - i32: sign-extended to i64
 * - i64: as-is
 * - f32: lower 32 bits (IEEE 754 bits)
 * - f64: as-is (IEEE 754 bits)
 * - structref/arrayref: gc_ref index (positive, 0 = null)
 * - funcref: function index (positive, 0 = null)
 * - i31: (value << 1) | 1 (tagged)
 * - null: 0
 */

#ifndef GC_HEAP_H
#define GC_HEAP_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Object kinds
#define GC_KIND_FREE   0
#define GC_KIND_STRUCT 1
#define GC_KIND_ARRAY  2

// GC flags
#define GC_FLAG_MARKED 0x01

/**
 * GC Object Header (16 bytes, aligned)
 *
 * Layout:
 *   [kind: u8][flags: u8][type_idx: u16][size: u32][field_count: u64]
 *
 * For structs: field_count stores the number of fields (to avoid scanning padding)
 * For arrays: field_count is unused (length is stored in data area)
 */
typedef struct GcHeader {
    uint8_t kind;       // GC_KIND_STRUCT or GC_KIND_ARRAY
    uint8_t flags;      // GC_FLAG_MARKED, etc.
    uint16_t type_idx;  // Type index in module
    uint32_t size;      // Total object size (including header)
    uint64_t reserved;  // For structs: field count; for arrays: unused
} GcHeader;

#define GC_HEADER_SIZE 16

/**
 * GC Heap structure
 *
 * The heap consists of:
 * 1. data: contiguous memory for objects
 * 2. object_table: mapping from gc_ref to object offset
 *
 * gc_ref values:
 * - 0 is reserved for null
 * - Actual objects start from gc_ref = 1
 */
typedef struct GcHeap {
    uint8_t* data;              // Heap memory
    size_t size;                // Current used size
    size_t capacity;            // Allocated capacity

    int32_t* object_table;      // gc_ref -> offset in data
    int32_t object_count;       // Number of objects (next gc_ref = object_count + 1)
    int32_t object_capacity;    // Capacity of object_table

    // Free list for GC (indices of freed objects)
    int32_t* free_list;
    int32_t free_count;
    int32_t free_capacity;

    // GC statistics
    int32_t total_allocations;
    int32_t total_collections;
} GcHeap;

// ============ Heap Lifecycle ============

/**
 * Create a new GC heap with the given initial capacity
 * @param initial_capacity Initial heap size in bytes
 * @return New heap, or NULL on allocation failure
 */
GcHeap* gc_heap_new(size_t initial_capacity);

/**
 * Free a GC heap and all its memory
 * @param heap Heap to free
 */
void gc_heap_free(GcHeap* heap);

// ============ Struct Operations ============

/**
 * Allocate a new struct
 * @param heap The GC heap
 * @param type_idx Type index in module
 * @param fields Array of field values (as int64_t)
 * @param num_fields Number of fields
 * @return gc_ref (1-based index), or 0 on failure
 */
int32_t gc_heap_alloc_struct(GcHeap* heap, int32_t type_idx,
                              const int64_t* fields, int32_t num_fields);

/**
 * Get a struct field value
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @param field_idx Field index
 * @return Field value as int64_t
 */
int64_t gc_heap_struct_get(GcHeap* heap, int32_t gc_ref, int32_t field_idx);

/**
 * Set a struct field value
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @param field_idx Field index
 * @param value New value as int64_t
 */
void gc_heap_struct_set(GcHeap* heap, int32_t gc_ref, int32_t field_idx, int64_t value);

// ============ Array Operations ============

/**
 * Allocate a new array
 * @param heap The GC heap
 * @param type_idx Type index in module
 * @param len Array length
 * @param init_value Initial value for all elements
 * @return gc_ref (1-based index), or 0 on failure
 */
int32_t gc_heap_alloc_array(GcHeap* heap, int32_t type_idx,
                             int32_t len, int64_t init_value);

/**
 * Allocate a new array from existing values
 * @param heap The GC heap
 * @param type_idx Type index in module
 * @param values Array of initial values
 * @param len Array length
 * @return gc_ref (1-based index), or 0 on failure
 */
int32_t gc_heap_alloc_array_from_values(GcHeap* heap, int32_t type_idx,
                                         const int64_t* values, int32_t len);

/**
 * Get array length
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @return Array length
 */
int32_t gc_heap_array_len(GcHeap* heap, int32_t gc_ref);

/**
 * Get an array element
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @param idx Element index
 * @return Element value as int64_t
 */
int64_t gc_heap_array_get(GcHeap* heap, int32_t gc_ref, int32_t idx);

/**
 * Set an array element
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @param idx Element index
 * @param value New value as int64_t
 */
void gc_heap_array_set(GcHeap* heap, int32_t gc_ref, int32_t idx, int64_t value);

/**
 * Fill array elements with a value
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @param offset Start offset
 * @param value Fill value
 * @param count Number of elements to fill
 */
void gc_heap_array_fill(GcHeap* heap, int32_t gc_ref, int32_t offset,
                        int64_t value, int32_t count);

/**
 * Copy array elements
 * @param heap The GC heap
 * @param dst_ref Destination array reference
 * @param dst_offset Destination offset
 * @param src_ref Source array reference
 * @param src_offset Source offset
 * @param count Number of elements to copy
 */
void gc_heap_array_copy(GcHeap* heap, int32_t dst_ref, int32_t dst_offset,
                        int32_t src_ref, int32_t src_offset, int32_t count);

// ============ Type Information ============

/**
 * Get the type index of an object
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @return Type index, or -1 for null/invalid
 */
int32_t gc_heap_get_type_idx(GcHeap* heap, int32_t gc_ref);

/**
 * Get the kind of an object (GC_KIND_STRUCT or GC_KIND_ARRAY)
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @return Object kind, or GC_KIND_FREE for null/invalid
 */
int32_t gc_heap_get_kind(GcHeap* heap, int32_t gc_ref);

/**
 * Check if a gc_ref is valid (non-null and within bounds)
 * @param heap The GC heap
 * @param gc_ref Object reference
 * @return 1 if valid, 0 otherwise
 */
int32_t gc_heap_is_valid(GcHeap* heap, int32_t gc_ref);

// ============ GC Operations ============

/**
 * Mark an object as reachable (for GC)
 * @param heap The GC heap
 * @param gc_ref Object reference to mark
 */
void gc_heap_mark(GcHeap* heap, int32_t gc_ref);

/**
 * Mark all objects reachable from roots
 * @param heap The GC heap
 * @param roots Array of root values (encoded as int64_t)
 * @param num_roots Number of roots
 */
void gc_heap_mark_roots(GcHeap* heap, const int64_t* roots, int32_t num_roots);

/**
 * Sweep unmarked objects
 * @param heap The GC heap
 * @return Number of objects collected
 */
int32_t gc_heap_sweep(GcHeap* heap);

/**
 * Perform a full GC cycle (mark + sweep)
 * @param heap The GC heap
 * @param roots Array of root values
 * @param num_roots Number of roots
 * @return Number of objects collected
 */
int32_t gc_heap_collect(GcHeap* heap, const int64_t* roots, int32_t num_roots);

// ============ Utilities ============

/**
 * Get heap base pointer (for JIT inline access)
 * @param heap The GC heap
 * @return Pointer to heap data
 */
uint8_t* gc_heap_get_base(GcHeap* heap);

/**
 * Get object offset in heap (for JIT inline access)
 * @param heap The GC heap
 * @param gc_ref Object reference (1-based)
 * @return Offset in heap data, or -1 for invalid
 */
int32_t gc_heap_get_offset(GcHeap* heap, int32_t gc_ref);

/**
 * Get current heap size (bytes used)
 * @param heap The GC heap
 * @return Current used size in bytes
 */
size_t gc_heap_get_size(GcHeap* heap);

/**
 * Get heap capacity (total allocated bytes)
 * @param heap The GC heap
 * @return Total capacity in bytes
 */
size_t gc_heap_get_capacity(GcHeap* heap);

/**
 * Get number of live objects
 * @param heap The GC heap
 * @return Number of objects (including freed ones in object table)
 */
int32_t gc_heap_get_object_count(GcHeap* heap);

/**
 * Get GC statistics
 * @param heap The GC heap
 * @param out_total_allocations Output: total allocations since creation
 * @param out_total_collections Output: total GC cycles performed
 */
void gc_heap_get_stats(GcHeap* heap, int32_t* out_total_allocations, int32_t* out_total_collections);

#ifdef __cplusplus
}
#endif

#endif // GC_HEAP_H
