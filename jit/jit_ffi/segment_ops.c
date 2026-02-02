// Copyright 2025
// Segment operations for bulk memory/table instructions

#include "jit_internal.h"
#include <string.h>
#include <stdlib.h>
#include <limits.h>

// ============ Per-Context Segment State ============
// Wasmtime-style: data/elem segments and their dropped bits live with the
// instance context (jit_context_t). JIT code never directly accesses these
// fields; only libcalls do.

static void free_data_segments(jit_context_t *ctx) {
    if (!ctx) return;

    if (ctx->data_segments) {
        for (int i = 0; i < ctx->data_segment_count; i++) {
            if (ctx->data_segments[i]) {
                moonbit_decref(ctx->data_segments[i]);
            }
        }
        free(ctx->data_segments);
        ctx->data_segments = NULL;
    }
    if (ctx->data_segment_sizes) { free(ctx->data_segment_sizes); ctx->data_segment_sizes = NULL; }
    if (ctx->data_dropped) { free(ctx->data_dropped); ctx->data_dropped = NULL; }
    ctx->data_segment_count = 0;
}

static void free_elem_segments(jit_context_t *ctx) {
    if (!ctx) return;

    if (ctx->elem_segments) {
        for (int i = 0; i < ctx->elem_segment_count; i++) {
            if (ctx->elem_segments[i]) {
                moonbit_decref(ctx->elem_segments[i]);
            }
        }
        free(ctx->elem_segments);
        ctx->elem_segments = NULL;
    }
    if (ctx->elem_segment_sizes) { free(ctx->elem_segment_sizes); ctx->elem_segment_sizes = NULL; }
    if (ctx->elem_dropped) { free(ctx->elem_dropped); ctx->elem_dropped = NULL; }
    ctx->elem_segment_count = 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_init_data_segments(int64_t ctx_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx) return;

    free_data_segments(ctx);
    if (count <= 0) return;

    ctx->data_segment_count = count;
    ctx->data_segments = (uint8_t **)calloc(count, sizeof(uint8_t *));
    ctx->data_segment_sizes = (size_t *)calloc(count, sizeof(size_t));
    ctx->data_dropped = (uint8_t *)calloc(count, sizeof(uint8_t));
}

// data: owned MoonBit FixedArray[Byte] payload pointer (may be NULL when size==0).
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_add_data_segment(
    int64_t ctx_ptr,
    int idx,
    uint8_t *data,
    int size,
    int is_dropped
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx || !ctx->data_segments || idx < 0 || idx >= ctx->data_segment_count) {
        if (data) moonbit_decref(data);
        return;
    }

    if (ctx->data_segments[idx]) {
        moonbit_decref(ctx->data_segments[idx]);
    }

    ctx->data_segments[idx] = data;
    ctx->data_segment_sizes[idx] = (size_t)size;
    ctx->data_dropped[idx] = is_dropped ? 1 : 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_init_elem_segments(int64_t ctx_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx) return;

    free_elem_segments(ctx);
    if (count <= 0) return;

    ctx->elem_segment_count = count;
    ctx->elem_segments = (int64_t **)calloc(count, sizeof(int64_t *));
    ctx->elem_segment_sizes = (size_t *)calloc(count, sizeof(size_t));
    ctx->elem_dropped = (uint8_t *)calloc(count, sizeof(uint8_t));
}

// data: owned MoonBit FixedArray[Int64] payload pointer storing pairs (value,type_idx).
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_add_elem_segment(
    int64_t ctx_ptr,
    int idx,
    int64_t *data,
    int size,
    int is_dropped
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx || !ctx->elem_segments || idx < 0 || idx >= ctx->elem_segment_count) {
        if (data) moonbit_decref(data);
        return;
    }

    if (ctx->elem_segments[idx]) {
        moonbit_decref(ctx->elem_segments[idx]);
    }

    ctx->elem_segments[idx] = data;
    ctx->elem_segment_sizes[idx] = (size_t)size;
    ctx->elem_dropped[idx] = is_dropped ? 1 : 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_clear_segments(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    if (!ctx) return;
    free_data_segments(ctx);
    free_elem_segments(ctx);
}

// ============ Memory Segment Libcalls ============

// memory.init - Initialize memory region from data segment
// Returns 0 on success, traps on out-of-bounds
static void memory_init_impl(
    jit_context_t *ctx,
    int32_t memidx,
    int32_t data_idx,
    int64_t dst,
    int64_t src,
    int64_t len
) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= ctx->data_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only len=0 is valid
    uint64_t len_u32 = (uint64_t)(uint32_t)len;
    uint64_t src_u32 = (uint64_t)(uint32_t)src;
    if (ctx->data_dropped && ctx->data_dropped[data_idx]) {
        if (len_u32 != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    uint8_t *seg_data = ctx->data_segments ? ctx->data_segments[data_idx] : NULL;
    size_t seg_size = ctx->data_segment_sizes ? ctx->data_segment_sizes[data_idx] : 0;

    // Bounds check source range in segment
    if ((uint64_t)seg_size < src_u32 || (uint64_t)seg_size - src_u32 < len_u32) {
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
    // For memory32, treat dst as u32; negative values represent high addresses.
    // For memory64, negative values are invalid and trap.
    uint64_t dst_off;
    if (memidx == 0 ? ctx->memory0->is_memory64 : ctx->memories[memidx]->is_memory64) {
        if (dst < 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return;
        }
        dst_off = (uint64_t)dst;
    } else {
        dst_off = (uint64_t)(uint32_t)dst;
    }
    if (mem_size < dst_off || mem_size - dst_off < len_u32) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Copy data
    if (len_u32 > 0) {
        memcpy(mem + dst_off, seg_data + src_u32, (size_t)len_u32);
    }
}

// data.drop - Mark data segment as dropped
static void data_drop_impl(
    jit_context_t *ctx,
    int32_t data_idx
) {
    if (!ctx || !ctx->data_dropped) return;

    // Bounds check (dropping out-of-bounds is a no-op in spec)
    if (data_idx >= 0 && data_idx < ctx->data_segment_count) {
        ctx->data_dropped[data_idx] = 1;
    }
}

// ============ Table Segment Libcalls ============

// table.fill - Fill table region with a value
static void table_fill_impl(
    jit_context_t *ctx,
    int32_t table_idx,
    int64_t dst,
    int64_t val,
    int64_t len
) {
    if (!ctx) {
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

    // Bounds check
    if (dst < 0 || len < 0 ||
        (uint64_t)table_size < (uint64_t)dst ||
        (uint64_t)table_size - (uint64_t)dst < (uint64_t)len) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Infer the type index for funcref values so call_indirect can type-check.
    // For non-funcref values, keep type_idx = -1.
    int64_t type_idx = -1;
    if (val != 0 && (val & FUNCREF_TAG) != 0 && g_func_table && g_func_type_indices) {
        void* raw_ptr = (void*)(uintptr_t)(val & ~FUNCREF_TAG);
        for (int i = 0; i < g_func_table_size; i++) {
            if (g_func_table[i] == raw_ptr) {
                type_idx = (int64_t)g_func_type_indices[i];
                break;
            }
        }
    } else if (val < 0 && g_func_type_indices) {
        // IR-encoded funcref index: -(func_idx + 1)
        int32_t func_idx = (int32_t)(-(val + 1));
        if (func_idx >= 0 && func_idx < g_num_funcs) {
            type_idx = (int64_t)g_func_type_indices[func_idx];
        }
    }

    // Fill (table entries are 2 slots: func_ptr and type_idx)
    for (int64_t i = 0; i < len; i++) {
        int64_t idx = (dst + i) * 2;
        table[idx] = (void *)(uintptr_t)val;               // value bits
        table[idx + 1] = (void *)(intptr_t)type_idx;       // type idx for funcref, -1 otherwise
    }
}

// table.copy - Copy table region
static void table_copy_impl(
    jit_context_t *ctx,
    int32_t dst_table_idx,
    int32_t src_table_idx,
    int64_t dst,
    int64_t src,
    int64_t len
) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

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
        (uint64_t)src_size < (uint64_t)src ||
        (uint64_t)src_size - (uint64_t)src < (uint64_t)len ||
        (uint64_t)dst_size < (uint64_t)dst ||
        (uint64_t)dst_size - (uint64_t)dst < (uint64_t)len) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Copy (handle overlapping regions correctly)
    // Each entry is 2 slots
    if (len > 0) {
        memmove(dst_table + dst * 2, src_table + src * 2, (size_t)len * 2 * sizeof(void *));
    }
}

// table.init - Initialize table from element segment
static void table_init_impl(
    jit_context_t *ctx,
    int32_t table_idx,
    int32_t elem_idx,
    int64_t dst,
    int64_t src,
    int64_t len
) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= ctx->elem_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only len=0 is valid
    if (ctx->elem_dropped && ctx->elem_dropped[elem_idx]) {
        if (len != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    int64_t *seg_data = ctx->elem_segments ? ctx->elem_segments[elem_idx] : NULL;
    size_t seg_size = ctx->elem_segment_sizes ? ctx->elem_segment_sizes[elem_idx] : 0;

    // Bounds check source range in segment
    if (src < 0 || len < 0 ||
        (uint64_t)seg_size < (uint64_t)src ||
        (uint64_t)seg_size - (uint64_t)src < (uint64_t)len) {
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
    if (dst < 0 ||
        (uint64_t)table_size < (uint64_t)dst ||
        (uint64_t)table_size - (uint64_t)dst < (uint64_t)len) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Copy elements (each element is stored as a pair: value + type_idx).
    for (int64_t i = 0; i < len; i++) {
        int64_t seg_off = (src + i) * 2;
        int64_t elem_val = seg_data[seg_off];
        int64_t elem_type = seg_data[seg_off + 1];
        int64_t tbl_off = (dst + i) * 2;
        table[tbl_off] = (void *)(uintptr_t)elem_val;
        table[tbl_off + 1] = (void *)(intptr_t)elem_type;
    }
}

// elem.drop - Mark element segment as dropped
static void elem_drop_impl(
    jit_context_t *ctx,
    int32_t elem_idx
) {
    if (!ctx || !ctx->elem_dropped) return;

    // Bounds check (dropping out-of-bounds is a no-op in spec)
    if (elem_idx >= 0 && elem_idx < ctx->elem_segment_count) {
        ctx->elem_dropped[elem_idx] = 1;
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

// Get element size in bytes for array.new_data/array.init_data.
// Returns 0 when the array element type has no defined byte size (e.g. refs).
static size_t get_array_elem_byte_size(int32_t type_idx) {
    if (!g_gc_type_cache || type_idx < 0 || type_idx >= g_gc_num_types) {
        return 0;
    }
    int kind = g_gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_KIND_OFF];
    if (kind != GC_KIND_ARRAY) {
        return 0;
    }
    int bytes = g_gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_ARRAY_ELEM_BYTES_OFF];
    if (bytes <= 0) {
        return 0;
    }
    return (size_t)bytes;
}

static int get_array_elem_tag(int32_t type_idx) {
    if (!g_gc_type_cache || type_idx < 0 || type_idx >= g_gc_num_types) {
        return 0;
    }
    int kind = g_gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_KIND_OFF];
    if (kind != GC_KIND_ARRAY) {
        return 0;
    }
    return g_gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_ARRAY_ELEM_TAG_OFF];
}

static inline uint16_t read_u16_le(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline uint32_t read_u32_le(const uint8_t *p) {
    return (uint32_t)p[0]
        | ((uint32_t)p[1] << 8)
        | ((uint32_t)p[2] << 16)
        | ((uint32_t)p[3] << 24);
}

static inline uint64_t read_u64_le(const uint8_t *p) {
    return (uint64_t)read_u32_le(p) | ((uint64_t)read_u32_le(p + 4) << 32);
}

static int64_t decode_array_elem_from_bytes(const uint8_t *p, int tag) {
    switch (tag) {
        case 1: // i8 (packed)
            return (int64_t)(uint8_t)p[0];
        case 2: // i16 (packed)
            return (int64_t)read_u16_le(p);
        case 3: // i32
        case 5: { // f32
            int32_t v = (int32_t)read_u32_le(p);
            return (int64_t)v;
        }
        case 4: // i64
        case 6: { // f64
            int64_t v = (int64_t)read_u64_le(p);
            return v;
        }
        default:
            return 0;
    }
}

// array.new_data - Create array from data segment
// Returns: encoded GC reference (gc_ref << 1)
static int64_t gc_array_new_data_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t data_idx,
    int64_t offset,
    int64_t length
) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= ctx->data_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t off_u32 = (uint32_t)offset;
    if (ctx->data_dropped && ctx->data_dropped[data_idx]) {
        if (len_u32 != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        // Return null array for dropped segment with length=0
        return 0;
    }

    // Get segment data
    uint8_t *seg_data = ctx->data_segments ? ctx->data_segments[data_idx] : NULL;
    size_t seg_size = ctx->data_segment_sizes ? ctx->data_segment_sizes[data_idx] : 0;

    // Calculate byte size needed
    size_t elem_size = get_array_elem_byte_size(type_idx);
    int elem_tag = get_array_elem_tag(type_idx);
    if (elem_size == 0) {
        // Validation should prevent this (ref element types have no data byte size),
        // but trap defensively.
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }
    uint64_t total_bytes = (uint64_t)len_u32 * (uint64_t)elem_size;

    // Bounds check source range in segment
    if ((uint64_t)seg_size < (uint64_t)off_u32 || (uint64_t)seg_size - (uint64_t)off_u32 < total_bytes) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }
    if (len_u32 > (uint32_t)INT32_MAX) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    int32_t gc_ref = gc_heap_alloc_array(g_gc_heap, type_idx, (int32_t)len_u32, 0);
    if (gc_ref == 0) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    const uint8_t *p = seg_data + (size_t)off_u32;
    for (uint32_t i = 0; i < len_u32; i++) {
        int64_t v = decode_array_elem_from_bytes(p + (size_t)i * elem_size, elem_tag);
        gc_heap_array_set(g_gc_heap, gc_ref, (int32_t)i, v);
    }

    return ((int64_t)gc_ref) << 1;
}

// array.new_elem - Create array from element segment
// Returns: encoded GC reference (gc_ref << 1)
static int64_t gc_array_new_elem_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t elem_idx,
    int64_t offset,
    int64_t length
) {
    (void)type_idx;
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= ctx->elem_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t off_u32 = (uint32_t)offset;
    if (ctx->elem_dropped && ctx->elem_dropped[elem_idx]) {
        if (len_u32 != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Get segment data
    int64_t *seg_data = ctx->elem_segments ? ctx->elem_segments[elem_idx] : NULL;
    size_t seg_size = ctx->elem_segment_sizes ? ctx->elem_segment_sizes[elem_idx] : 0;

    // Bounds check source range in segment
    if ((uint64_t)seg_size < (uint64_t)off_u32 || (uint64_t)seg_size - (uint64_t)off_u32 < (uint64_t)len_u32) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }
    if (len_u32 > (uint32_t)INT32_MAX) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    int32_t gc_ref = gc_heap_alloc_array(g_gc_heap, type_idx, (int32_t)len_u32, 0);
    if (gc_ref == 0) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    for (uint32_t i = 0; i < len_u32; i++) {
        int64_t seg_off = ((int64_t)off_u32 + (int64_t)i) * 2;
        int64_t v = seg_data[seg_off];
        gc_heap_array_set(g_gc_heap, gc_ref, (int32_t)i, v);
    }

    return ((int64_t)gc_ref) << 1;
}

// array.init_data - Initialize array region from data segment
static void gc_array_init_data_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t data_idx,
    int64_t array_ref,
    int64_t arr_offset,
    int64_t data_offset,
    int64_t length
) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= ctx->data_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t data_off_u32 = (uint32_t)data_offset;
    uint32_t arr_off_u32 = (uint32_t)arr_offset;
    if (ctx->data_dropped && ctx->data_dropped[data_idx]) {
        if (len_u32 != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    uint8_t *seg_data = ctx->data_segments ? ctx->data_segments[data_idx] : NULL;
    size_t seg_size = ctx->data_segment_sizes ? ctx->data_segment_sizes[data_idx] : 0;
    size_t elem_size = get_array_elem_byte_size(type_idx);
    int elem_tag = get_array_elem_tag(type_idx);
    if (elem_size == 0) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    uint64_t total_bytes = (uint64_t)len_u32 * (uint64_t)elem_size;

    // Bounds check source range in segment
    if ((uint64_t)seg_size < (uint64_t)data_off_u32 || (uint64_t)seg_size - (uint64_t)data_off_u32 < total_bytes) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    if (array_ref == 0) {
        g_trap_code = 3;  // null array reference
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    int32_t gc_ref = (int32_t)(array_ref >> 1);
    int32_t array_len = gc_heap_array_len(g_gc_heap, gc_ref);
    if ((uint64_t)array_len < (uint64_t)arr_off_u32 || (uint64_t)array_len - (uint64_t)arr_off_u32 < (uint64_t)len_u32) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    const uint8_t *p = seg_data + (size_t)data_off_u32;
    for (uint32_t i = 0; i < len_u32; i++) {
        int64_t v = decode_array_elem_from_bytes(p + (size_t)i * elem_size, elem_tag);
        gc_heap_array_set(g_gc_heap, gc_ref, (int32_t)(arr_off_u32 + i), v);
    }
}

// array.init_elem - Initialize array region from element segment
static void gc_array_init_elem_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t elem_idx,
    int64_t array_ref,
    int64_t arr_offset,
    int64_t elem_offset,
    int64_t length
) {
    (void)type_idx;
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= ctx->elem_segment_count) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t elem_off_u32 = (uint32_t)elem_offset;
    uint32_t arr_off_u32 = (uint32_t)arr_offset;
    if (ctx->elem_dropped && ctx->elem_dropped[elem_idx]) {
        if (len_u32 != 0) {
            g_trap_code = 1;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Get segment data
    int64_t *seg_data = ctx->elem_segments ? ctx->elem_segments[elem_idx] : NULL;
    size_t seg_size = ctx->elem_segment_sizes ? ctx->elem_segment_sizes[elem_idx] : 0;

    // Bounds check source range in segment
    if ((uint64_t)seg_size < (uint64_t)elem_off_u32 || (uint64_t)seg_size - (uint64_t)elem_off_u32 < (uint64_t)len_u32) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    if (array_ref == 0) {
        g_trap_code = 3;  // null array reference
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    int32_t gc_ref = (int32_t)(array_ref >> 1);
    int32_t array_len = gc_heap_array_len(g_gc_heap, gc_ref);
    if ((uint64_t)array_len < (uint64_t)arr_off_u32 || (uint64_t)array_len - (uint64_t)arr_off_u32 < (uint64_t)len_u32) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    for (uint32_t i = 0; i < len_u32; i++) {
        int64_t seg_off = ((int64_t)elem_off_u32 + (int64_t)i) * 2;
        int64_t v = seg_data[seg_off];
        gc_heap_array_set(g_gc_heap, gc_ref, (int32_t)(arr_off_u32 + i), v);
    }
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
