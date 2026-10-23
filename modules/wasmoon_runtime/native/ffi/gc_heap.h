/**
 * GC Heap for WebAssembly GC Types
 *
 * This file implements a unified GC heap that can be used by both
 * the interpreter and JIT-compiled code. All GC objects (structs and arrays)
 * are stored in a contiguous memory region managed by C.
 *
 * Value Encoding
 *
 * Untyped low-level allocations use a 16-byte slot of two int64_t words.
 * Typed Store objects use GcTypeLayout offsets and widths instead.
 * Only v128 uses the high word; every other value kind
 * lives entirely in the low word and stores zero in the high word:
 * - i32: sign-extended to i64
 * - i64: as-is
 * - f32: lower 32 bits (IEEE 754 bits)
 * - f64: as-is (IEEE 754 bits)
 * - v128: low 8 bytes in `lo`, high 8 bytes in `hi` (little-endian lane order)
 * - structref/arrayref: gc_ref index (positive, 0 = null)
 * - funcref: function index (positive, 0 = null)
 * - i31: (value << 1) | 1 (tagged)
 * - null: 0
 *
 * The int64_t accessors below address the low word, which is where every
 * reference lives, so they keep their meaning for all non-v128 values. Use
 * the `_wide` accessors to read or write a full slot.
 */

#ifndef GC_HEAP_H
#define GC_HEAP_H

#include <stdint.h>
#include <stddef.h>
#include "quota.h"

#ifdef __cplusplus
extern "C" {
#endif

// Object kinds
#define GC_KIND_FREE   0
#define GC_KIND_STRUCT 1
#define GC_KIND_ARRAY  2

// GC flags
#define GC_FLAG_MARKED 0x01

// Exception snapshots are outside the object table and have a distinct word tag.
#define GC_EXCEPTION_REF_TAG INT64_C(0x1000000000000000)

struct native_exception_arena;
typedef int32_t (*GcAllocationPolicy)(void *, int32_t);
typedef int32_t (*GcCollectionPolicy)(void *, void *, int32_t);

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
 * One field or array element.
 *
 * `lo` is the runtime word every non-v128 value is encoded into, and is the
 * only word the collector scans for references -- a reference is never
 * written to `hi`, so scanning it could only add false positives.
 */
typedef struct GcSlot {
    int64_t lo;
    int64_t hi;
} GcSlot;

#define GC_VALUE_SLOT_SIZE 16

/**
 * Byte offset from the start of an array's payload to its first element.
 *
 * The length is an int32_t at offset 0; the rest is padding that exists to
 * keep element slots 16-byte aligned.
 */
#define GC_ARRAY_DATA_OFFSET 16

/**
 * GC Heap structure
 *
 * The heap consists of:
 * 1. data: contiguous memory for objects
 * 2. identity_pages: sparse mapping from gc_ref to offset and runtime type
 * 3. live_objects: ordered traversal independent of historical identities
 *
 * gc_ref values:
 * - 0 is reserved for null
 * - Actual objects start from gc_ref = 1
 */
// Immutable, Store-canonical physical layouts. Reference words retain the
// existing 64-bit encoding; narrow scalar fields do not inherit V128 width.
typedef struct { int32_t offset, width, reference; } GcFieldLayout;
typedef struct {
    int32_t kind, count, size, reference_count;
    // Exact four-bit width/reference codes for the first sixteen fields.
    uint64_t prefix_shape;
    GcFieldLayout fields[];
} GcTypeLayout;

// Identities are never recycled by collection. Empty descriptor pages can be
// released without making an old identity designate a different object.
#define GC_ID_PAGE_BITS 10
#define GC_ID_PAGE_SIZE (1 << GC_ID_PAGE_BITS)
typedef struct {
    int32_t offsets[GC_ID_PAGE_SIZE];
    int32_t runtime_types[GC_ID_PAGE_SIZE];
    int32_t live_count;
    uint32_t visit_epochs[GC_ID_PAGE_SIZE];
} GcIdentityPage;

typedef struct GcHeap {
    uint8_t* data;              // Heap memory
    size_t size;                // Current used size
    size_t capacity;            // Allocated capacity
    size_t collection_limit;    // Allocation budget, independent of physical capacity

    GcTypeLayout **layouts;
    int32_t layout_capacity;
    uint32_t trace_epoch;
    GcIdentityPage **identity_pages;
    int32_t identity_page_capacity;
    int32_t object_count;       // High-water identity; next gc_ref = count + 1
    int32_t *live_objects;      // Ascending identities of currently live payloads
    int32_t live_count;
    int32_t live_capacity;

    // Free list for GC (indices of freed objects)
    int32_t* free_list;
    int32_t free_count;
    int32_t free_capacity;

    // GC statistics
    int32_t total_allocations;
    int32_t total_collections;
    int32_t barrier_writes;

    // Runtime-owned registrations for precise roots held by parked native JIT
    // continuations that share this Store heap.
    void *parked_jit_roots_head;
    GcCollectionPolicy collection_policy;
    void *collection_state;    // RC-retained MoonBit coordinator, no heap back-reference
    struct native_continuation_arena *continuation_arena; // Borrowed through root registrations
    struct native_exception_arena *exception_arena; // Borrowed through root registrations
    wasmoon_reservation_t *byte_reservation;
    wasmoon_reservation_t *object_reservation;
    int quota_denied; // 1: payload bytes, 2: retained identity slots
    int32_t precise_roots; // Native marking view; MoonBit updates it outside a collection
    GcAllocationPolicy allocation_policy; // Closed MoonBit function; no retained closure
    int32_t exception_root_count; // Leases borrowing exception_arena
    int32_t continuation_root_count; // Leases borrowing continuation_arena
} GcHeap;

static inline GcIdentityPage *gc_heap_identity_page(GcHeap *heap, int32_t ref) {
    if (!heap || ref <= 0 || ref > heap->object_count) return NULL;
    return heap->identity_pages[(ref - 1) >> GC_ID_PAGE_BITS];
}

static inline int32_t gc_heap_identity_offset(GcHeap *heap, int32_t ref) {
    GcIdentityPage *page = gc_heap_identity_page(heap, ref);
    return page ? page->offsets[(ref - 1) & (GC_ID_PAGE_SIZE - 1)] : -1;
}

static inline int32_t gc_heap_runtime_type(GcHeap *heap, int32_t ref) {
    GcIdentityPage *page = gc_heap_identity_page(heap, ref);
    return page ? page->runtime_types[(ref - 1) & (GC_ID_PAGE_SIZE - 1)] : -1;
}

static inline void gc_heap_set_runtime_type(GcHeap *heap, int32_t ref, int32_t type) {
    GcIdentityPage *page = gc_heap_identity_page(heap, ref);
    if (page) page->runtime_types[(ref - 1) & (GC_ID_PAGE_SIZE - 1)] = type;
}

int32_t gc_heap_register_object(GcHeap *heap, int32_t offset);
int gc_heap_fast_allocation_enabled(void);

static inline GcTypeLayout *gc_heap_layout(GcHeap *heap, int32_t identity) {
    return heap && identity >= 0 && identity < heap->layout_capacity ? heap->layouts[identity] : NULL;
}

static inline GcTypeLayout *gc_object_layout(GcHeap *heap, const GcHeader *header) {
    return gc_heap_layout(heap, (int32_t)(header->reserved >> 32) - 1);
}

GcSlot gc_layout_read(const uint8_t *data, const GcFieldLayout *field);
void gc_layout_write(uint8_t *data, const GcFieldLayout *field, GcSlot value);
int32_t gc_heap_alloc_typed(GcHeap *heap, int32_t identity, int32_t local_type,
    int32_t count, const void *values, int wide, int repeated, GcSlot init);
void gc_heap_maybe_verify(GcHeap *heap, const char *op_name);
int gc_should_fail_allocation(void);
int gc_heap_admit(GcHeap *heap, size_t size);
void gc_heap_undo_admission(GcHeap *heap);
int gc_heap_ensure_payload_capacity(GcHeap *heap, size_t needed);

// Budgeted heaps enter the common allocator before any guest payload write.
static inline uint8_t *gc_heap_allocation_limit(GcHeap *heap) {
    size_t limit = heap->capacity;
    if (heap->precise_roots && heap->collection_limit < limit) limit = heap->collection_limit;
    return heap->data + (heap->byte_reservation ? heap->size : limit);
}

static inline GcHeap *gc_heap_live(GcHeap *heap) {
    return heap && heap->data ? heap : NULL;
}

// ============ Heap Lifecycle ============

/**
 * Register an updateable root array and retain its heap with MoonBit RC.
 * The continuation or exception arena must unregister exactly once.
 * The heap borrows its registration list; the registration owns its root slots.
 */
int32_t gc_heap_register_parked_roots(
    GcHeap* heap,
    int32_t root_count,
    void** out_registration,
    int64_t** out_roots
);

/**
 * Remove and free one parked-root registration.
 */
void gc_heap_unregister_parked_roots(void* registration);

int32_t gc_heap_bind_exception_roots(void *registration,
    struct native_exception_arena *arena, int64_t reference);
GcHeap *gc_heap_registration_heap(void *registration);
int32_t gc_heap_bind_continuation_roots(void *registration,
    struct native_continuation_arena *arena, int64_t reference);
int32_t gc_heap_registered_root_count(void *registration);
void gc_heap_copy_registered_roots(void *registration, int64_t *roots);
void continuation_arena_mark(struct native_continuation_arena *arena, int64_t reference);
int32_t continuation_arena_marked_count(struct native_continuation_arena *arena);
void continuation_arena_copy_marked(struct native_continuation_arena *arena, int64_t *roots);
void continuation_arena_reset_marks(struct native_continuation_arena *arena);
void continuation_arena_sweep(struct native_continuation_arena *arena, GcHeap *heap);

void exception_arena_mark(struct native_exception_arena *arena, int64_t reference);
int32_t exception_arena_marked_count(struct native_exception_arena *arena);
void exception_arena_copy_marked(struct native_exception_arena *arena, int64_t *roots);
void exception_arena_reset_marks(struct native_exception_arena *arena);
void exception_arena_sweep(struct native_exception_arena *arena, GcHeap *heap);

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

/**
 * Allocate a struct from full slots, so v128 fields keep their high word.
 *
 * `gc_heap_alloc_struct` above takes runtime words and is what JIT-emitted
 * code calls; it zeroes each high word. Callers that can hold a v128 -- the
 * interpreter -- use this instead.
 */
int32_t gc_heap_alloc_struct_wide(GcHeap* heap, int32_t type_idx,
                                   const GcSlot* fields, int32_t num_fields);

/**
 * Read a whole struct field, high word included.
 */
GcSlot gc_heap_struct_get_wide(GcHeap* heap, int32_t gc_ref, int32_t field_idx);

/**
 * Write a whole struct field, high word included.
 */
void gc_heap_struct_set_wide(GcHeap* heap, int32_t gc_ref, int32_t field_idx,
                             GcSlot value);

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
 * Array counterparts of the struct `_wide` entry points above: same storage,
 * same reason, for callers that can hold a v128.
 */
int32_t gc_heap_alloc_array_wide(GcHeap* heap, int32_t type_idx,
                                  int32_t len, GcSlot init_value);

int32_t gc_heap_alloc_array_from_slots(GcHeap* heap, int32_t type_idx,
                                        const GcSlot* values, int32_t len);

GcSlot gc_heap_array_get_wide(GcHeap* heap, int32_t gc_ref, int32_t idx);

void gc_heap_array_set_wide(GcHeap* heap, int32_t gc_ref, int32_t idx,
                            GcSlot value);

void gc_heap_array_fill_wide(GcHeap* heap, int32_t gc_ref, int32_t offset,
                             GcSlot value, int32_t count);

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

/**
 * Write barrier hook for reference stores.
 * Current collector is non-generational; this is a debug hook/assertion point.
 */
void gc_heap_write_barrier(GcHeap* heap, int32_t owner_gc_ref, int64_t written_value);

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

// Copy active roots belonging to this heap, or count them when roots is NULL.
int32_t jit_copy_active_gc_roots(GcHeap *heap, int64_t *roots);

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

/**
 * Verify internal heap invariants and object graph integrity.
 * @param heap The GC heap
 * @param verbose Print diagnostics to stderr when verification fails
 * @return 1 if valid, 0 if invariant violation detected
 */
int32_t gc_heap_verify(GcHeap* heap, int32_t verbose);

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
 * Discard unreachable objects allocated after an earlier object-table boundary.
 * Objects reachable from roots or parked JIT roots retain their gc_ref identity.
 * @param roots Encoded Store roots that survive the rollback.
 * @param num_roots Number of entries in roots.
 * @return 1 on success, 0 for an invalid boundary.
 */
int32_t gc_heap_rollback_allocations(
    GcHeap* heap,
    int32_t object_count,
    const int64_t* roots,
    int32_t num_roots
);

/**
 * Get number of write-barrier calls recorded.
 */
int32_t gc_heap_get_barrier_writes(GcHeap* heap);

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

int gc_heap_ensure_object_capacity(GcHeap *heap);
