// Copyright 2025
// Segment operations for bulk memory/table instructions

#include "jit_internal.h"
#include <string.h>
#include <stdlib.h>

// ============ Thread-Local Segment State ============
// Set up before JIT execution, cleared after
// We store pointers to MoonBit FixedArrays directly (no copying needed)
// MoonBit GC doesn't move objects, so pointers remain valid
// We receive owned parameters and call moonbit_decref on cleanup
// Using __thread for thread-safety (each thread has its own segments)

// Data segments - pointers to MoonBit FixedArray[Byte] data (owned)
static __thread uint8_t **g_data_segments = NULL;
static __thread size_t *g_data_segment_sizes = NULL;
static __thread uint8_t *g_data_dropped = NULL;
static __thread int g_data_segment_count = 0;

// Element segments - pointers to MoonBit FixedArray[Int64] data (owned)
static __thread int64_t **g_elem_segments = NULL;
static __thread size_t *g_elem_segment_sizes = NULL;
static __thread uint8_t *g_elem_dropped = NULL;
static __thread int g_elem_segment_count = 0;

// ============ Setup/Teardown Functions ============

// Helper to free data segment storage and decref MoonBit objects
static void free_data_segment_storage(void) {
    if (g_data_segments) {
        for (int i = 0; i < g_data_segment_count; i++) {
            if (g_data_segments[i]) {
                // Decref the MoonBit FixedArray we took ownership of
                moonbit_decref(g_data_segments[i]);
            }
        }
        free(g_data_segments);
        g_data_segments = NULL;
    }
    if (g_data_segment_sizes) { free(g_data_segment_sizes); g_data_segment_sizes = NULL; }
    if (g_data_dropped) { free(g_data_dropped); g_data_dropped = NULL; }
    g_data_segment_count = 0;
}

// Helper to free element segment storage and decref MoonBit objects
static void free_elem_segment_storage(void) {
    if (g_elem_segments) {
        for (int i = 0; i < g_elem_segment_count; i++) {
            if (g_elem_segments[i]) {
                // Decref the MoonBit FixedArray we took ownership of
                moonbit_decref(g_elem_segments[i]);
            }
        }
        free(g_elem_segments);
        g_elem_segments = NULL;
    }
    if (g_elem_segment_sizes) { free(g_elem_segment_sizes); g_elem_segment_sizes = NULL; }
    if (g_elem_dropped) { free(g_elem_dropped); g_elem_dropped = NULL; }
    g_elem_segment_count = 0;
}

// Initialize data segment storage with a given count
// This clears any existing state and allocates space for count segments
MOONBIT_FFI_EXPORT void wasmoon_jit_init_data_segments(int count) {
    // Clear any existing state
    free_data_segment_storage();

    if (count <= 0) {
        return;
    }

    g_data_segment_count = count;
    g_data_segments = (uint8_t **)calloc(count, sizeof(uint8_t *));
    g_data_segment_sizes = (size_t *)calloc(count, sizeof(size_t));
    g_data_dropped = (uint8_t *)calloc(count, sizeof(uint8_t));
}

// Add a single data segment - stores pointer directly (no copy)
// idx: segment index (must be < count passed to init)
// data: pointer to MoonBit FixedArray[Byte] data (owned - we take ownership)
// size: number of bytes
MOONBIT_FFI_EXPORT void wasmoon_jit_add_data_segment(
    int idx,
    uint8_t *data,
    int size
) {
    if (idx < 0 || idx >= g_data_segment_count || !g_data_segments) {
        // Can't store, must decref to avoid leak
        if (data) moonbit_decref(data);
        return;
    }

    g_data_segment_sizes[idx] = (size_t)size;
    g_data_dropped[idx] = 0;

    // Store pointer directly - we own this reference (owned parameter)
    // No copy needed since MoonBit GC doesn't move objects
    g_data_segments[idx] = data;
}

// Initialize element segment storage with a given count
// This clears any existing state and allocates space for count segments
MOONBIT_FFI_EXPORT void wasmoon_jit_init_elem_segments(int count) {
    // Clear any existing state
    free_elem_segment_storage();

    if (count <= 0) {
        return;
    }

    g_elem_segment_count = count;
    g_elem_segments = (int64_t **)calloc(count, sizeof(int64_t *));
    g_elem_segment_sizes = (size_t *)calloc(count, sizeof(size_t));
    g_elem_dropped = (uint8_t *)calloc(count, sizeof(uint8_t));
}

// Add a single element segment - stores pointer directly (no copy)
// idx: segment index (must be < count passed to init)
// data: pointer to MoonBit FixedArray[Int64] data (owned - we take ownership)
// size: number of elements
MOONBIT_FFI_EXPORT void wasmoon_jit_add_elem_segment(
    int idx,
    int64_t *data,
    int size
) {
    if (idx < 0 || idx >= g_elem_segment_count || !g_elem_segments) {
        // Can't store, must decref to avoid leak
        if (data) moonbit_decref(data);
        return;
    }

    g_elem_segment_sizes[idx] = (size_t)size;
    g_elem_dropped[idx] = 0;

    // Store pointer directly - we own this reference (owned parameter)
    // No copy needed since MoonBit GC doesn't move objects
    g_elem_segments[idx] = data;
}

// Clear all segment state after JIT execution
MOONBIT_FFI_EXPORT void wasmoon_jit_clear_segments(void) {
    free_data_segment_storage();
    free_elem_segment_storage();
}

// ============ Memory Segment Libcalls ============

// memory.init - Initialize memory region from data segment
// Returns 0 on success, traps on out-of-bounds
static void memory_init_impl(
    jit_context_t *ctx,
    int32_t memidx,
    int32_t data_idx,
    int32_t dst,
    int32_t src,
    int32_t len
) {
    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= g_data_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only len=0 is valid
    if (g_data_dropped[data_idx]) {
        if (len != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    uint8_t *seg_data = g_data_segments[data_idx];
    size_t seg_size = g_data_segment_sizes[data_idx];

    // Bounds check source range in segment
    if (src < 0 || len < 0 || (size_t)(src + len) > seg_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Get memory
    uint8_t *mem = NULL;
    size_t mem_size = 0;
    if (memidx == 0) {
        if (!ctx->memory0 || !ctx->memory0->base) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return;
        }
        mem = ctx->memory0->base;
        mem_size = atomic_load_explicit(&ctx->memory0->current_length, memory_order_relaxed);
    } else if (ctx->memories && memidx < ctx->memory_count) {
        wasmoon_memory_t *m = ctx->memories[memidx];
        if (!m || !m->base) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return;
        }
        mem = m->base;
        mem_size = atomic_load_explicit(&m->current_length, memory_order_relaxed);
    } else {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check destination range in memory
    if (dst < 0 || (size_t)(dst + len) > mem_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Copy data
    if (len > 0) {
        memcpy(mem + dst, seg_data + src, len);
    }
}

// data.drop - Mark data segment as dropped
static void data_drop_impl(
    jit_context_t *ctx,
    int32_t data_idx
) {
    (void)ctx;

    // Bounds check (dropping out-of-bounds is a no-op in spec)
    if (data_idx >= 0 && data_idx < g_data_segment_count) {
        g_data_dropped[data_idx] = 1;
    }
}

// ============ Table Segment Libcalls ============

// table.fill - Fill table region with a value
static void table_fill_impl(
    jit_context_t *ctx,
    int32_t table_idx,
    int32_t dst,
    int64_t val,
    int32_t len
) {
    // Get table
    void **table;
    size_t table_size;

    if (table_idx == 0) {
        table = ctx->table0_base;
        table_size = ctx->table0_elements;
    } else if (ctx->tables && table_idx < ctx->table_count) {
        table = ctx->tables[table_idx];
        table_size = ctx->table_sizes[table_idx];
    } else {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check
    if (dst < 0 || len < 0 || (size_t)(dst + len) > table_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Fill (table entries are 2 slots: func_ptr and type_idx)
    for (int i = 0; i < len; i++) {
        int idx = (dst + i) * 2;
        table[idx] = (void *)(uintptr_t)val;  // func_ptr or ref value
        table[idx + 1] = (void *)(intptr_t)(-1);  // type_idx (unknown for filled values)
    }
}

// table.copy - Copy table region
static void table_copy_impl(
    jit_context_t *ctx,
    int32_t dst_table_idx,
    int32_t src_table_idx,
    int32_t dst,
    int32_t src,
    int32_t len
) {
    // Get source table
    void **src_table;
    size_t src_size;
    if (src_table_idx == 0) {
        src_table = ctx->table0_base;
        src_size = ctx->table0_elements;
    } else if (ctx->tables && src_table_idx < ctx->table_count) {
        src_table = ctx->tables[src_table_idx];
        src_size = ctx->table_sizes[src_table_idx];
    } else {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Get destination table
    void **dst_table;
    size_t dst_size;
    if (dst_table_idx == 0) {
        dst_table = ctx->table0_base;
        dst_size = ctx->table0_elements;
    } else if (ctx->tables && dst_table_idx < ctx->table_count) {
        dst_table = ctx->tables[dst_table_idx];
        dst_size = ctx->table_sizes[dst_table_idx];
    } else {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check
    if (src < 0 || dst < 0 || len < 0 ||
        (size_t)(src + len) > src_size ||
        (size_t)(dst + len) > dst_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Copy (handle overlapping regions correctly)
    // Each entry is 2 slots
    if (len > 0) {
        memmove(dst_table + dst * 2, src_table + src * 2, len * 2 * sizeof(void *));
    }
}

// table.init - Initialize table from element segment
static void table_init_impl(
    jit_context_t *ctx,
    int32_t table_idx,
    int32_t elem_idx,
    int32_t dst,
    int32_t src,
    int32_t len
) {
    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= g_elem_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only len=0 is valid
    if (g_elem_dropped[elem_idx]) {
        if (len != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    int64_t *seg_data = g_elem_segments[elem_idx];
    size_t seg_size = g_elem_segment_sizes[elem_idx];

    // Bounds check source range in segment
    if (src < 0 || len < 0 || (size_t)(src + len) > seg_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Get table
    void **table;
    size_t table_size;
    if (table_idx == 0) {
        table = ctx->table0_base;
        table_size = ctx->table0_elements;
    } else if (ctx->tables && table_idx < ctx->table_count) {
        table = ctx->tables[table_idx];
        table_size = ctx->table_sizes[table_idx];
    } else {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check destination range in table
    if (dst < 0 || (size_t)(dst + len) > table_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Copy elements (each table entry is 2 slots: func_ptr and type_idx)
    for (int i = 0; i < len; i++) {
        int64_t elem_val = seg_data[src + i];
        int tbl_idx = (dst + i) * 2;
        table[tbl_idx] = (void *)(uintptr_t)elem_val;
        table[tbl_idx + 1] = (void *)(intptr_t)(-1);  // type_idx unknown
    }
}

// elem.drop - Mark element segment as dropped
static void elem_drop_impl(
    jit_context_t *ctx,
    int32_t elem_idx
) {
    (void)ctx;

    // Bounds check (dropping out-of-bounds is a no-op in spec)
    if (elem_idx >= 0 && elem_idx < g_elem_segment_count) {
        g_elem_dropped[elem_idx] = 1;
    }
}

// ============ Function Pointer Getters ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_init_ptr(void) {
    return (int64_t)memory_init_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_data_drop_ptr(void) {
    return (int64_t)data_drop_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_fill_ptr(void) {
    return (int64_t)table_fill_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_copy_ptr(void) {
    return (int64_t)table_copy_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_init_ptr(void) {
    return (int64_t)table_init_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_elem_drop_ptr(void) {
    return (int64_t)elem_drop_impl;
}

// ============ GC Array Segment Operations ============
// These require access to data/elem segments AND the GC heap
// g_gc_heap is already declared in jit_internal.h

// Get element size in bytes for a given array type
// type_idx encodes the element type in the lower bits
static size_t get_elem_byte_size(int32_t type_idx) {
    // Extract element type from type_idx
    // This is a simplified version - actual implementation would use type cache
    // For now, assume type_idx directly encodes element size category:
    // 0 = i8 (1 byte), 1 = i16 (2 bytes), 2 = i32/f32 (4 bytes), 3 = i64/f64 (8 bytes)
    // In practice, the element size should be looked up from the type cache
    int elem_type = type_idx & 0x3;
    switch (elem_type) {
        case 0: return 1;  // i8
        case 1: return 2;  // i16
        case 2: return 4;  // i32/f32
        case 3: return 8;  // i64/f64/ref
        default: return 8;
    }
}

// array.new_data - Create array from data segment
// Returns: encoded GC reference (gc_ref << 1)
static int64_t gc_array_new_data_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t data_idx,
    int32_t offset,
    int32_t length
) {
    (void)ctx;

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= g_data_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // If segment is dropped, only length=0 is valid
    if (g_data_dropped[data_idx]) {
        if (length != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        // Return null array for dropped segment with length=0
        return 0;
    }

    // Get segment data
    uint8_t *seg_data = g_data_segments[data_idx];
    size_t seg_size = g_data_segment_sizes[data_idx];

    // Calculate byte size needed
    size_t elem_size = get_elem_byte_size(type_idx);
    size_t total_bytes = (size_t)length * elem_size;

    // Bounds check source range in segment
    if (offset < 0 || length < 0 || (size_t)(offset + total_bytes) > seg_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // For now, trap since we need GC heap integration
    // TODO: Allocate array in GC heap and copy data
    g_trap_code = 1;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    return 0;
}

// array.new_elem - Create array from element segment
// Returns: encoded GC reference (gc_ref << 1)
static int64_t gc_array_new_elem_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t elem_idx,
    int32_t offset,
    int32_t length
) {
    (void)ctx; (void)type_idx;

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= g_elem_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // If segment is dropped, only length=0 is valid
    if (g_elem_dropped[elem_idx]) {
        if (length != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Get segment data
    size_t seg_size = g_elem_segment_sizes[elem_idx];

    // Bounds check source range in segment
    if (offset < 0 || length < 0 || (size_t)(offset + length) > seg_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // For now, trap since we need GC heap integration
    // TODO: Allocate array in GC heap and copy elements
    g_trap_code = 1;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    return 0;
}

// array.init_data - Initialize array region from data segment
static void gc_array_init_data_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t data_idx,
    int64_t array_ref,
    int32_t arr_offset,
    int32_t data_offset,
    int32_t length
) {
    (void)ctx; (void)type_idx; (void)array_ref; (void)arr_offset;

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= g_data_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only length=0 is valid
    if (g_data_dropped[data_idx]) {
        if (length != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    size_t seg_size = g_data_segment_sizes[data_idx];
    size_t elem_size = get_elem_byte_size(type_idx);
    size_t total_bytes = (size_t)length * elem_size;

    // Bounds check source range in segment
    if (data_offset < 0 || length < 0 || (size_t)(data_offset + total_bytes) > seg_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // For now, trap since we need GC heap integration to access array
    // TODO: Get array from GC heap and copy data into it
    g_trap_code = 1;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
}

// array.init_elem - Initialize array region from element segment
static void gc_array_init_elem_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t elem_idx,
    int64_t array_ref,
    int32_t arr_offset,
    int32_t elem_offset,
    int32_t length
) {
    (void)ctx; (void)type_idx; (void)array_ref; (void)arr_offset;

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= g_elem_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only length=0 is valid
    if (g_elem_dropped[elem_idx]) {
        if (length != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    size_t seg_size = g_elem_segment_sizes[elem_idx];

    // Bounds check source range in segment
    if (elem_offset < 0 || length < 0 || (size_t)(elem_offset + length) > seg_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // For now, trap since we need GC heap integration to access array
    // TODO: Get array from GC heap and copy elements into it
    g_trap_code = 1;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
}

// GC array segment function pointer getters
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_data_ptr(void) {
    return (int64_t)gc_array_new_data_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_elem_ptr(void) {
    return (int64_t)gc_array_new_elem_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_init_data_ptr(void) {
    return (int64_t)gc_array_init_data_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_init_elem_ptr(void) {
    return (int64_t)gc_array_init_elem_impl;
}
