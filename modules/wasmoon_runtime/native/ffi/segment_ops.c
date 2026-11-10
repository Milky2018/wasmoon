// Copyright 2025
// Segment operations for bulk memory/table instructions

#include "jit_internal.h"
#include "native_env.h"
#include "gc_access.h"
#include "callable_lookup.h"
#include <string.h>
#include <stdlib.h>
#include <limits.h>

// ============ Per-Context Segment State ============
// Wasmtime-style: data/elem segments and their dropped bits live with the
// instance context (jit_context_t). JIT code never directly accesses these
// fields; only libcalls do.

static int table_debug_cached = -1;

static int table_debug_enabled(void) {
    if (table_debug_cached < 0) {
        const char *v = getenv("WASMOON_TABLE_DEBUG");
        table_debug_cached = wasmoon_native_env_truthy(v) ? 1 : 0;
    }
    return table_debug_cached;
}

static int segment_count(const void *segments) {
    return segments ? Moonbit_array_length(segments) : 0;
}

static inline int segment_range_fits(uint64_t size, uint64_t offset, uint64_t length) {
    return offset <= size && length <= size - offset;
}

static jit_segments_state_t *ensure_segments(jit_context_t *ctx) {
    if (!ctx_runtime(ctx)->segments)
        ctx_runtime(ctx)->segments = wasmoon_native_calloc(1, sizeof(jit_segments_state_t));
    return ctx_runtime(ctx)->segments;
}

static void free_data_segments(jit_context_t *ctx) {
    if (ctx_runtime(ctx)->segments->data_segments)
        moonbit_decref(ctx_runtime(ctx)->segments->data_segments);
    ctx_runtime(ctx)->segments->data_segments = NULL;
}

static void free_elem_segments(jit_context_t *ctx) {
    if (ctx_runtime(ctx)->segments->elem_segments)
        moonbit_decref(ctx_runtime(ctx)->segments->elem_segments);
    ctx_runtime(ctx)->segments->elem_segments = NULL;
}

void ctx_clear_segments_internal(jit_context_t *ctx) {
    if (!ctx || !ctx_runtime(ctx)->segments) return;
    free_data_segments(ctx);
    free_elem_segments(ctx);
    if (ctx_runtime(ctx)->segments->data_dropped) moonbit_decref(ctx_runtime(ctx)->segments->data_dropped);
    if (ctx_runtime(ctx)->segments->elem_dropped) moonbit_decref(ctx_runtime(ctx)->segments->elem_dropped);
    free(ctx_runtime(ctx)->segments);
    ctx_runtime(ctx)->segments = NULL;
}

extern int64_t wasmoon_jit_context_ptr(void *jit_context);

MOONBIT_FFI_EXPORT void wasmoon_jit_bind_segment_drop_flags(void *context, uint8_t *data, uint8_t *elements) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    if (!ctx || !ensure_segments(ctx)) return;
    moonbit_incref(data);
    moonbit_incref(elements);
    if (ctx_runtime(ctx)->segments->data_dropped) moonbit_decref(ctx_runtime(ctx)->segments->data_dropped);
    if (ctx_runtime(ctx)->segments->elem_dropped) moonbit_decref(ctx_runtime(ctx)->segments->elem_dropped);
    ctx_runtime(ctx)->segments->data_dropped = data;
    ctx_runtime(ctx)->segments->elem_dropped = elements;
}

static int data_is_dropped(jit_context_t *ctx, int32_t index) {
    uint8_t *flags = ctx_segments_state(ctx)->data_dropped;
    return flags && index >= 0 && index < Moonbit_array_length(flags) && flags[index];
}

static int elem_is_dropped(jit_context_t *ctx, int32_t index) {
    uint8_t *flags = ctx_segments_state(ctx)->elem_dropped;
    return flags && index >= 0 && index < Moonbit_array_length(flags) && flags[index];
}

// Consume private outer arrays built by MoonBit. Guest drop mutates these
// arrays, so they must not alias another context's outer arrays.
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_bind_segments(
    void *context, uint8_t **data, int64_t **elements
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    if (!ctx) {
        moonbit_decref(data);
        moonbit_decref(elements);
        return 0;
    }
    if (!segment_count(data) && !segment_count(elements)) {
        ctx_clear_segments_internal(ctx);
        moonbit_decref(data);
        moonbit_decref(elements);
        return 1;
    }
    if (!ensure_segments(ctx)) {
        moonbit_decref(data);
        moonbit_decref(elements);
        return 0;
    }
    free_data_segments(ctx);
    free_elem_segments(ctx);
    ctx_runtime(ctx)->segments->data_segments = data;
    ctx_runtime(ctx)->segments->elem_segments = elements;
    return 1;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_clear_segments_managed(
    void *jit_context
) {
    ctx_clear_segments_internal((jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(jit_context));
}

// ============ Memory Segment Libcalls ============

// memory.init - Initialize memory region from data segment
// Returns 0 on success, traps on out-of-bounds
static void WASMOON_GUEST_ABI memory_init_impl(
    jit_context_t *ctx,
    int32_t memidx,
    int32_t data_idx,
    int64_t dst,
    int64_t src,
    int64_t len
) {
    if (!ctx) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= segment_count(ctx_segments_state(ctx)->data_segments)) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }

    uint64_t len_u32 = (uint64_t)(uint32_t)len;
    uint64_t src_u32 = (uint64_t)(uint32_t)src;
    uint8_t *seg_data = ctx_segments_state(ctx)->data_segments ? ctx_segments_state(ctx)->data_segments[data_idx] : NULL;
    size_t seg_size = data_is_dropped(ctx, data_idx) ? 0 : (size_t)Moonbit_array_length(seg_data);
    // Dropped segments are empty; both ranges must still be checked.

    // Bounds check source range in segment
    if (!segment_range_fits(seg_size, src_u32, len_u32)) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }

    wasmoon_memory_t *memory = NULL;
    if (memidx == 0) {
        memory = ctx_memory0(ctx);
    } else if (memidx > 0 && ctx_memories(ctx) && memidx < ctx_memory_count(ctx)) {
        memory = ctx_memories(ctx)[memidx];
    }
    if (!memory || !memory->base) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }
    uint8_t *mem = memory->base;
    size_t mem_size = atomic_load_explicit(&memory->current_length, memory_order_relaxed);

    // Bounds check destination range in memory
    // For memory32, treat dst as u32; negative values represent high addresses.
    // For memory64, negative values are invalid and trap.
    uint64_t dst_off;
    if (memory->is_memory64) {
        if (dst < 0) {
            jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
            return;
        }
        dst_off = (uint64_t)dst;
    } else {
        dst_off = (uint64_t)(uint32_t)dst;
    }
    if (!segment_range_fits(mem_size, dst_off, len_u32)) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }

    // Copy data
    if (len_u32 > 0) {
        memcpy(mem + dst_off, seg_data + src_u32, (size_t)len_u32);
    }
}

// data.drop - Mark data segment as dropped
static void WASMOON_GUEST_ABI data_drop_impl(
    jit_context_t *ctx,
    int32_t data_idx
) {
    if (!ctx || !ctx_segments_state(ctx)->data_segments) return;

    // Bounds check (dropping out-of-bounds is a no-op in spec)
    if (data_idx >= 0 && data_idx < segment_count(ctx_segments_state(ctx)->data_segments)) {
        if (ctx_runtime(ctx)->segments->data_dropped && data_idx < Moonbit_array_length(ctx_runtime(ctx)->segments->data_dropped))
            ctx_runtime(ctx)->segments->data_dropped[data_idx] = 1;
        if (Moonbit_array_length(ctx_runtime(ctx)->segments->data_segments[data_idx]) == 0) return;
        moonbit_decref(ctx_runtime(ctx)->segments->data_segments[data_idx]);
        ctx_runtime(ctx)->segments->data_segments[data_idx] = moonbit_make_bytes(0, 0);
    }
}

// ============ Table Segment Libcalls ============

// Table entries use Store callable identities, including growth initializers.
int64_t table_type_for_value(jit_context_t *ctx, int64_t val) {
    if (!ctx) return -1;
    // Infer the type index for funcref values so call_indirect can type-check.
    // For non-funcref values, keep type_idx = -1.
    int64_t type_idx = callable_type_for_value(ctx, val);
    if (
        type_idx < 0 &&
        val != 0 &&
        (val & FUNCREF_TAG) != 0 &&
        ctx_runtime(ctx)->gc_func_table &&
        ctx_runtime(ctx)->gc_func_type_indices
    ) {
        void* raw_ptr = (void*)(uintptr_t)(val & ~FUNCREF_TAG);
        for (int i = 0; i < ctx_runtime(ctx)->gc_func_table_size; i++) {
            if (ctx_runtime(ctx)->gc_func_table[i] == (int64_t)(uintptr_t)raw_ptr) {
                int32_t t = ctx_runtime(ctx)->gc_func_type_indices[i];
                if (ctx_runtime(ctx)->gc_canonical_indices && t >= 0 && t < ctx_runtime(ctx)->gc_num_canonical) {
                    t = ctx_runtime(ctx)->gc_canonical_indices[t];
                }
                type_idx = (int64_t)t;
                break;
            }
        }
    } else if (type_idx < 0 && val < 0 && ctx_runtime(ctx)->gc_func_type_indices) {
        // IR-encoded funcref index: -(func_idx + 1)
        int32_t func_idx = (int32_t)(-(val + 1));
        if (func_idx >= 0 && func_idx < ctx_runtime(ctx)->gc_num_funcs) {
            int32_t t = ctx_runtime(ctx)->gc_func_type_indices[func_idx];
            if (ctx_runtime(ctx)->gc_canonical_indices && t >= 0 && t < ctx_runtime(ctx)->gc_num_canonical) {
                t = ctx_runtime(ctx)->gc_canonical_indices[t];
            }
            type_idx = (int64_t)t;
        }
    }

    return type_idx;
}

// Lookup is nontrapping; callers report bounds failure before reading entries.
static inline void **find_table_entry(jit_context_t *ctx, int32_t table_idx, int64_t index) {
    if (ctx && table_idx >= 0 && table_idx < ctx_table_count(ctx) && index >= 0) {
        wasmoon_table_binding_t *bindings = ctx_runtime(ctx)->table_bindings;
        if (bindings) {
            // Context bindings retain the stable owner; growth and close update
            // its live layout. Avoid decoding the VMContext array fields again.
            const wasmoon_table_t *table = bindings[table_idx].owner;
            if ((uint64_t)index < table->size)
                return table->entries + (size_t)index * 2;
        } else {
            void ***tables = ctx_tables(ctx);
            const size_t *sizes = ctx_table_sizes(ctx);
            if (tables && sizes && (uint64_t)index < sizes[table_idx])
                return tables[table_idx] + (size_t)index * 2;
        }
    }
    return NULL;
}

static int64_t WASMOON_GUEST_ABI table_get_impl(jit_context_t *ctx, int32_t table_idx, int64_t index) {
    void **entry = find_table_entry(ctx, table_idx, index);
    if (!entry) return jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
    int64_t value = (int64_t)(intptr_t)entry[0];

    return value;
}

// Reference identity may exist before executable code is registered. Resolve
// only at a call boundary, never by reinterpreting a Store handle as a pointer.
// Optimize the read-only type/entry queries together at the call boundary.
#if defined(_MSC_VER)
static __forceinline
#else
static inline __attribute__((always_inline))
#endif
int64_t callable_entry_inline(jit_context_t *ctx, int64_t value) {
    int trap = 0;
    if (!value) trap = WASMOON_TRAP_NULL_REFERENCE;
    else {
        value = callable_native_reference_inline(ctx, value);
        if (value < 0) {
            int64_t index = -(value + 1);
            value = ctx && index < ctx_func_count(ctx)
                ? (int64_t)(intptr_t)ctx_func_table(ctx)[index] : 0;
        } else if ((value & STORE_FUNCREF_TAG) == STORE_FUNCREF_TAG) {
            value = 0; // No executable mapping yet; the reference remains live.
        } else if (value & FUNCREF_TAG) value &= ~FUNCREF_TAG;
        else value = 0;
        if (!value) trap = WASMOON_TRAP_BACKEND;
    }
    if (trap) return jit_trap_result(trap);
    return value;
}

int64_t callable_entry(jit_context_t *ctx, int64_t value) {
    return callable_entry_inline(ctx, value);
}

static int64_t WASMOON_GUEST_ABI funcref_call_target_impl(jit_context_t *ctx, int64_t value) {
    return callable_entry(ctx, value);
}

static int64_t WASMOON_GUEST_ABI function_reference_impl(jit_context_t *ctx, int32_t index) {
    if (!ctx || index < 0 || index >= ctx_func_count(ctx)) return 0;
    jit_runtime_state_t *state = ctx_runtime(ctx);
    if (index < state->callable_function_count) {
        int32_t address = state->callable_functions[index];
        if (address >= 0) return STORE_FUNCREF_TAG | ((int64_t)address + 1);
    }
    int64_t pointer = (int64_t)(intptr_t)ctx_func_table(ctx)[index];
    return pointer ? pointer | FUNCREF_TAG : -(int64_t)(index + 1);
}

#if defined(_MSC_VER)
__declspec(noinline)
#else
__attribute__((noinline))
#endif
static int64_t WASMOON_GUEST_ABI table_call_target_legacy(jit_context_t *ctx,
    int64_t value, int32_t actual, int32_t expected) {
    if (!callable_subtype(ctx, actual, expected))
        return jit_trap_result(WASMOON_TRAP_INDIRECT_TYPE);
    return callable_entry_inline(ctx, value);
}

static int64_t WASMOON_GUEST_ABI table_call_target_impl(jit_context_t *ctx, int32_t table_idx, int64_t index, int32_t expected) {
    void **entry = find_table_entry(ctx, table_idx, index);
    if (!entry) return jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
    int64_t value = (int64_t)(intptr_t)entry[0];
    if (!value) return jit_trap_result(WASMOON_TRAP_UNINITIALIZED_ELEMENT);
    int64_t exact = callable_exact_store_target(ctx_runtime(ctx), value, expected);
    if (exact) return exact;
    int32_t actual = callable_type_for_value_inline(ctx, value);
    if (actual < 0 && !ctx_runtime(ctx)->callable_registry)
        actual = (int32_t)(intptr_t)entry[1];
    if (!ctx_runtime(ctx)->callable_local_types)
        return table_call_target_legacy(ctx, value, actual, expected);
    if (!callable_subtype_registered(ctx_runtime(ctx), actual, expected))
        return jit_trap_result(WASMOON_TRAP_INDIRECT_TYPE);
    return callable_entry_inline(ctx, value);
}

// Bulk operations use the VMContext table view, including zero-sized tables.
static inline int read_bulk_table(jit_context_t *ctx, int32_t index,
    void ***entries, size_t *size) {
    if (!ctx || index < 0) return 0;
    if (index == 0) {
        *entries = ctx_table0_base(ctx);
        *size = ctx_table0_elements(ctx);
    } else {
        void ***tables = ctx_tables(ctx);
        const size_t *sizes = ctx_table_sizes(ctx);
        if (!tables || !sizes || index >= ctx_table_count(ctx)) return 0;
        *entries = tables[index];
        *size = sizes[index];
    }
    return *entries || *size == 0;
}

// table.fill - Fill table region with a value
static void WASMOON_GUEST_ABI table_fill_impl(
    jit_context_t *ctx,
    int32_t table_idx,
    int64_t dst,
    int64_t val,
    int64_t len
) {
    void **table;
    size_t table_size;
    if (!read_bulk_table(ctx, table_idx, &table, &table_size)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Bounds check
    if (dst < 0 || len < 0 ||
        !segment_range_fits(table_size, (uint64_t)dst, (uint64_t)len)) {
        if (table_debug_enabled()) {
            fprintf(
                stderr,
                "[TABLE FILL] trap table=%d dst=%lld len=%lld size=%zu val=%lld\n",
                (int)table_idx,
                (long long)dst,
                (long long)len,
                table_size,
                (long long)val
            );
        }
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // A registered Store reference already has the representation stored
    // by the generic path. Keep unresolved identities and debug tracing on
    // that path. The range check above covers both entry words.
    if (len == 1 && table_debug_cached == 0 && val >= 0 &&
        (val & STORE_FUNCREF_TAG) == STORE_FUNCREF_TAG) {
        int32_t canonical = callable_type_for_value_inline(ctx, val);
        if (canonical >= 0) {
            void **entry = table + (size_t)dst * 2;
            entry[0] = (void *)(uintptr_t)val;
            entry[1] = (void *)(intptr_t)canonical;
            table_mark_mutated(ctx, table_idx);
            return;
        }
    }

    int64_t type_idx = table_type_for_value(ctx, val);

    if (ctx_runtime(ctx)->table_bindings && ctx_runtime(ctx)->table_bindings[table_idx].owner &&
        ctx_runtime(ctx)->table_bindings[table_idx].owner->store_references)
        val = callable_store_reference(ctx, val);

    // Fill (table entries are 2 slots: func_ptr and type_idx)
    for (int64_t i = 0; i < len; i++) {
        int64_t idx = (dst + i) * 2;
        table[idx] = (void *)(uintptr_t)val;               // value bits
        table[idx + 1] = (void *)(intptr_t)type_idx;       // type idx for funcref, -1 otherwise
    }

    if (len > 0) table_mark_mutated(ctx, table_idx);

    if (table_debug_enabled() && table_idx == 0) {
        int64_t max_dump = table_size < 6 ? (int64_t)table_size : 6;
        fprintf(
            stderr,
            "[TABLE FILL] ok dst=%lld len=%lld val=%lld type=%lld size=%zu\n",
            (long long)dst,
            (long long)len,
            (long long)val,
            (long long)type_idx,
            table_size
        );
        for (int64_t i = 0; i < max_dump; i++) {
            int64_t raw = (int64_t)(uintptr_t)table[i * 2];
            int64_t ty = (int64_t)(intptr_t)table[i * 2 + 1];
            fprintf(stderr, "[TABLE FILL] table0[%lld]={raw=%lld,type=%lld}\n", (long long)i, (long long)raw, (long long)ty);
        }
    }
}

// table.copy - Copy table region
static void WASMOON_GUEST_ABI table_copy_impl(
    jit_context_t *ctx,
    int32_t dst_table_idx,
    int32_t src_table_idx,
    int64_t dst,
    int64_t src,
    int64_t len
) {
    void **src_table, **dst_table;
    size_t src_size, dst_size;
    if (!read_bulk_table(ctx, src_table_idx, &src_table, &src_size) ||
        !read_bulk_table(ctx, dst_table_idx, &dst_table, &dst_size)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Bounds check
    if (src < 0 || dst < 0 || len < 0 ||
        !segment_range_fits(src_size, (uint64_t)src, (uint64_t)len) ||
        !segment_range_fits(dst_size, (uint64_t)dst, (uint64_t)len)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Copy (handle overlapping regions correctly)
    // Each entry is 2 slots
    if (len > 0) {
        memmove(dst_table + dst * 2, src_table + src * 2, (size_t)len * 2 * sizeof(void *));
        table_mark_mutated(ctx, dst_table_idx);
    }
}

// table.init - Initialize table from element segment
static void WASMOON_GUEST_ABI table_init_impl(
    jit_context_t *ctx,
    int32_t table_idx,
    int32_t elem_idx,
    int64_t dst,
    int64_t src,
    int64_t len
) {
    if (!ctx) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= segment_count(ctx_segments_state(ctx)->elem_segments)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Get segment data
    int64_t *seg_data = ctx_segments_state(ctx)->elem_segments ? ctx_segments_state(ctx)->elem_segments[elem_idx] : NULL;
    size_t seg_size = elem_is_dropped(ctx, elem_idx) ? 0 : (size_t)Moonbit_array_length(seg_data) / 2;
    // Dropped segments remain subject to source and destination bounds checks.

    // Bounds check source range in segment
    if (src < 0 || len < 0 ||
        !segment_range_fits(seg_size, (uint64_t)src, (uint64_t)len)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    void **table;
    size_t table_size;
    if (!read_bulk_table(ctx, table_idx, &table, &table_size)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Bounds check destination range in table
    if (dst < 0 ||
        !segment_range_fits(table_size, (uint64_t)dst, (uint64_t)len)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // Copy elements (each element is stored as a pair: value + type_idx).
    for (int64_t i = 0; i < len; i++) {
        int64_t seg_off = (src + i) * 2;
        int64_t elem_val = seg_data[seg_off];
        int64_t elem_type = seg_data[seg_off + 1];
        int64_t tbl_off = (dst + i) * 2;
        if (ctx_runtime(ctx)->table_bindings && ctx_runtime(ctx)->table_bindings[table_idx].owner &&
            ctx_runtime(ctx)->table_bindings[table_idx].owner->store_references)
            elem_val = callable_store_reference(ctx, elem_val);
        table[tbl_off] = (void *)(uintptr_t)elem_val;
        table[tbl_off + 1] = (void *)(intptr_t)elem_type;
    }
    if (len > 0) table_mark_mutated(ctx, table_idx);
}

// elem.drop - Mark element segment as dropped
static void WASMOON_GUEST_ABI elem_drop_impl(
    jit_context_t *ctx,
    int32_t elem_idx
) {
    if (!ctx || !ctx_segments_state(ctx)->elem_segments) return;

    // Bounds check (dropping out-of-bounds is a no-op in spec)
    if (elem_idx >= 0 && elem_idx < segment_count(ctx_segments_state(ctx)->elem_segments)) {
        if (ctx_runtime(ctx)->segments->elem_dropped && elem_idx < Moonbit_array_length(ctx_runtime(ctx)->segments->elem_dropped))
            ctx_runtime(ctx)->segments->elem_dropped[elem_idx] = 1;
        if (Moonbit_array_length(ctx_runtime(ctx)->segments->elem_segments[elem_idx]) == 0) return;
        moonbit_decref(ctx_runtime(ctx)->segments->elem_segments[elem_idx]);
        ctx_runtime(ctx)->segments->elem_segments[elem_idx] = moonbit_make_int64_array(0, 0);
    }
}

// ============ Function Pointer Getters ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_init_ptr(void) {
    return WASMOON_GUEST_ADDRESS(memory_init_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_data_drop_ptr(void) {
    return WASMOON_GUEST_ADDRESS(data_drop_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_get_ptr(void) {
    return WASMOON_GUEST_ADDRESS(table_get_impl);
}
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_funcref_call_target_ptr(void) {
    return WASMOON_GUEST_ADDRESS(funcref_call_target_impl);
}
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_function_reference_ptr(void) {
    return WASMOON_GUEST_ADDRESS(function_reference_impl);
}
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_call_target_ptr(void) {
    return WASMOON_GUEST_ADDRESS(table_call_target_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_fill_ptr(void) {
    return WASMOON_GUEST_ADDRESS(table_fill_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_copy_ptr(void) {
    return WASMOON_GUEST_ADDRESS(table_copy_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_init_ptr(void) {
    return WASMOON_GUEST_ADDRESS(table_init_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_elem_drop_ptr(void) {
    return WASMOON_GUEST_ADDRESS(elem_drop_impl);
}

// ============ GC Array Segment Operations ============
// These require access to data/elem segments AND the GC heap

// Get element size in bytes for array.new_data/array.init_data.
// Returns 0 when the array element type has no defined byte size (e.g. refs).
static size_t get_array_elem_byte_size(jit_context_t *ctx, int32_t type_idx) {
    if (!ctx || !ctx_runtime(ctx)->gc_type_cache || type_idx < 0 || type_idx >= ctx_runtime(ctx)->gc_num_types) {
        return 0;
    }
    int kind = ctx_runtime(ctx)->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_KIND_OFF];
    if (kind != GC_KIND_ARRAY) {
        return 0;
    }
    int bytes = ctx_runtime(ctx)->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_ARRAY_ELEM_BYTES_OFF];
    if (bytes <= 0) {
        return 0;
    }
    return (size_t)bytes;
}

static int get_array_elem_tag(jit_context_t *ctx, int32_t type_idx) {
    if (!ctx || !ctx_runtime(ctx)->gc_type_cache || type_idx < 0 || type_idx >= ctx_runtime(ctx)->gc_num_types) {
        return 0;
    }
    int kind = ctx_runtime(ctx)->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_KIND_OFF];
    if (kind != GC_KIND_ARRAY) {
        return 0;
    }
    return ctx_runtime(ctx)->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_ARRAY_ELEM_TAG_OFF];
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

static GcSlot decode_array_elem_from_bytes(const uint8_t *p, int tag) {
    GcSlot value = {0, 0};
    switch (tag) {
        case 1: // i8 (packed)
            value.lo = (uint8_t)p[0];
            break;
        case 2: // i16 (packed)
            value.lo = read_u16_le(p);
            break;
        case 3: // i32
        case 5: // f32
            value.lo = (int32_t)read_u32_le(p);
            break;
        case 4: // i64
        case 6: // f64
            value.lo = (int64_t)read_u64_le(p);
            break;
        case 8: // v128
            value.lo = (int64_t)read_u64_le(p);
            value.hi = (int64_t)read_u64_le(p + 8);
            break;
        default:
            break;
    }
    return value;
}

static inline int compact_numeric_segment_layout(const GcTypeLayout *layout,
    size_t width, int tag) {
    static const uint8_t widths[] = {0, 1, 2, 4, 8, 4, 8, 0, 16};
    const uint16_t endian = 1;
    return *(const uint8_t *)&endian == 1 && tag > 0 && tag < 9 &&
        widths[tag] == width && layout && layout->kind == GC_KIND_ARRAY &&
        !layout->fields[0].reference && layout->size == (int32_t)width;
}

// Callers have checked the complete source and destination ranges. Segment
// Bytes are owned separately from heap payloads. Known numeric layouts have
// no reference barriers; legacy slots keep their checked per-element adapter.
static inline int try_initialize_array_data(GcHeap *heap, int32_t ref, int32_t offset,
    const uint8_t *source, int32_t count, size_t width, int tag) {
    GcHeader *header = gc_access_object_header(heap, ref);
    GcTypeLayout *layout = header ? gc_object_layout(heap, header) : NULL;
    if (compact_numeric_segment_layout(layout, width, tag)) {
        memcpy((uint8_t *)(header + 1) + GC_ARRAY_DATA_OFFSET + (size_t)offset * width,
            source, (size_t)count * width);
        gc_access_verify(heap, "array_data_init");
        return 1;
    }
    return 0;
}

static int32_t segment_array_identity(jit_context_t *ctx, int32_t type) {
    const jit_runtime_state_t *state = ctx_runtime(ctx);
    return state->callable_local_types && type >= 0 && type < state->callable_local_type_count
        ? state->callable_local_types[type] : -1;
}

// Segment constructors share the ordinary Store-canonical physical layout.
// This remains a single non-collecting attempt: segment admission and trap
// ordering stay with the caller, and legacy embeddings retain wide slots.
static int32_t allocate_segment_array(GcHeap *heap, const GcTypeLayout *layout,
    int32_t identity, int32_t type, int32_t count) {
    return layout && layout->kind == GC_KIND_ARRAY
        ? gc_heap_alloc_typed(heap, identity, type, count, NULL, 1, 1, (GcSlot){0, 0})
        : gc_heap_alloc_array(heap, type, count, 0);
}

// array.new_data - Create array from data segment
// Returns the encoded native GC reference.
static int64_t WASMOON_GUEST_ABI gc_array_new_data_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t data_idx,
    int64_t offset,
    int64_t length
) {
    int allow_collection = 1;
check_segment:
    if (!ctx || !ctx_gc_heap(ctx)) {
        return jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
    }
    GcHeap *heap = (GcHeap *)ctx_gc_heap(ctx);

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= segment_count(ctx_segments_state(ctx)->data_segments)) {
        return jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t off_u32 = (uint32_t)offset;
    // Get segment data
    uint8_t *seg_data = ctx_segments_state(ctx)->data_segments ? ctx_segments_state(ctx)->data_segments[data_idx] : NULL;
    size_t seg_size = data_is_dropped(ctx, data_idx) ? 0 : (size_t)Moonbit_array_length(seg_data);

    // Calculate byte size needed
    size_t elem_size = get_array_elem_byte_size(ctx, type_idx);
    int elem_tag = get_array_elem_tag(ctx, type_idx);
    if (elem_size == 0) {
        // Validation should prevent this (ref element types have no data byte size),
        // but trap defensively.
        return jit_trap_result(WASMOON_TRAP_UNREACHABLE);
    }
    uint64_t total_bytes = (uint64_t)len_u32 * (uint64_t)elem_size;

    // Bounds check source range in segment
    if (!segment_range_fits(seg_size, off_u32, total_bytes)) {
        return jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
    }

    if (len_u32 > (uint32_t)INT32_MAX) {
        return jit_trap_result(WASMOON_TRAP_UNREACHABLE);
    }

    const uint8_t *p = seg_data ? seg_data + (size_t)off_u32 : NULL;
    int32_t identity = segment_array_identity(ctx, type_idx);
    GcTypeLayout *layout = gc_heap_layout(heap, identity);
    int packed = p && len_u32 && gc_verify_env_cached == 0 &&
        compact_numeric_segment_layout(layout, elem_size, elem_tag);
    int32_t gc_ref;
    if (packed) {
        gc_ref = gc_heap_alloc_typed_array_data(
            heap, layout, identity, type_idx, (int32_t)len_u32, p, allow_collection);
        if (gc_ref > 0) return gc_heap_ref_word(heap, gc_ref);
    } else if (allow_collection &&
        compact_numeric_segment_layout(layout, elem_size, elem_tag) &&
        gc_heap_segment_needs_collection(heap)) {
        gc_ref = GC_SEGMENT_NEEDS_COLLECTION;
    } else {
        gc_ref = allocate_segment_array(heap, layout, identity, type_idx, (int32_t)len_u32);
    }
    if (gc_ref <= 0) {
        if (gc_ref == GC_SEGMENT_NEEDS_COLLECTION) {
            int collection_kind = packed ? GC_COLLECTION_PACKED_SEGMENT : GC_COLLECTION_ALLOCATION;
            if (gc_collect_for_alloc_indexed_internal(ctx, NULL, 0, NULL, collection_kind, NULL, 1) >= 0) {
                // The root visitor can change the embedding. Read the entire
                // segment and type again before borrowing payload or allocating.
                allow_collection = 0;
                goto check_segment;
            }
            g_trap_code = WASMOON_TRAP_MISSING_ROOTS;
        } else {
            g_trap_code = WASMOON_TRAP_OUT_OF_MEMORY;
        }
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }

    if (len_u32 < 4 ||
        !try_initialize_array_data(heap, gc_ref, 0, p, (int32_t)len_u32, elem_size, elem_tag)) {
        for (uint32_t i = 0; i < len_u32; i++) {
            GcSlot value = decode_array_elem_from_bytes(p + (size_t)i * elem_size, elem_tag);
            gc_heap_array_set_wide(heap, gc_ref, (int32_t)i, value);
        }
    }

    return gc_heap_ref_word(heap, gc_ref);
}

// array.new_elem - Create array from element segment
// Returns the encoded native GC reference.
static int64_t WASMOON_GUEST_ABI gc_array_new_elem_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t elem_idx,
    int64_t offset,
    int64_t length
) {
    if (!ctx || !ctx_gc_heap(ctx)) {
        return jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
    }
    GcHeap *heap = (GcHeap *)ctx_gc_heap(ctx);

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= segment_count(ctx_segments_state(ctx)->elem_segments)) {
        return jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t off_u32 = (uint32_t)offset;
    // Get segment data
    int64_t *seg_data = ctx_segments_state(ctx)->elem_segments ? ctx_segments_state(ctx)->elem_segments[elem_idx] : NULL;
    size_t seg_size = elem_is_dropped(ctx, elem_idx) ? 0 : (size_t)Moonbit_array_length(seg_data) / 2;

    // Bounds check source range in segment
    if ((uint64_t)seg_size < (uint64_t)off_u32 || (uint64_t)seg_size - (uint64_t)off_u32 < (uint64_t)len_u32) {
        return jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
    }

    if (len_u32 > (uint32_t)INT32_MAX) {
        return jit_trap_result(WASMOON_TRAP_UNREACHABLE);
    }

    int32_t identity = segment_array_identity(ctx, type_idx);
    int32_t gc_ref = allocate_segment_array(heap, gc_heap_layout(heap, identity),
        identity, type_idx, (int32_t)len_u32);
    if (gc_ref == 0) {
        return jit_trap_result(WASMOON_TRAP_OUT_OF_MEMORY);
    }

    for (uint32_t i = 0; i < len_u32; i++) {
        int64_t seg_off = ((int64_t)off_u32 + (int64_t)i) * 2;
        int64_t v = seg_data[seg_off];
        gc_heap_array_set(heap, gc_ref, (int32_t)i, v);
    }

    return gc_heap_ref_word(heap, gc_ref);
}

// array.init_data - Initialize array region from data segment
static void WASMOON_GUEST_ABI gc_array_init_data_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t data_idx,
    int64_t array_ref,
    int64_t arr_offset,
    int64_t data_offset,
    int64_t length
) {
    if (!ctx || !ctx_gc_heap(ctx)) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }
    GcHeap *heap = (GcHeap *)ctx_gc_heap(ctx);

    // Bounds check data segment index
    if (data_idx < 0 || data_idx >= segment_count(ctx_segments_state(ctx)->data_segments)) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t data_off_u32 = (uint32_t)data_offset;
    uint32_t arr_off_u32 = (uint32_t)arr_offset;
    if (array_ref == 0) {
        jit_trap_result(WASMOON_TRAP_NULL_REFERENCE);
        return;
    }

    int32_t gc_ref = gc_heap_ref_id(heap, array_ref);
    GcHeader *header = gc_access_object_header(heap, gc_ref);
    int32_t array_len = header ? *(const int32_t *)(header + 1) : 0;
    if (!segment_range_fits((uint64_t)array_len, arr_off_u32, len_u32)) {
        jit_trap_result(WASMOON_TRAP_ARRAY_BOUNDS);
        return;
    }

    // Get segment data
    uint8_t *seg_data = ctx_segments_state(ctx)->data_segments ? ctx_segments_state(ctx)->data_segments[data_idx] : NULL;
    size_t seg_size = data_is_dropped(ctx, data_idx) ? 0 : (size_t)Moonbit_array_length(seg_data);
    size_t elem_size = get_array_elem_byte_size(ctx, type_idx);
    int elem_tag = get_array_elem_tag(ctx, type_idx);
    if (elem_size == 0) {
        jit_trap_result(WASMOON_TRAP_UNREACHABLE);
        return;
    }
    uint64_t total_bytes = (uint64_t)len_u32 * (uint64_t)elem_size;

    // Bounds check source range in segment
    if (!segment_range_fits(seg_size, data_off_u32, total_bytes)) {
        jit_trap_result(WASMOON_TRAP_MEMORY_BOUNDS);
        return;
    }

    const uint8_t *p = seg_data ? seg_data + (size_t)data_off_u32 : NULL;
    // No call can relocate this validated destination between admission and
    // the numeric copy. Keep the checked setters for other layouts and
    // verification of short writes.
    if (len_u32 >= 2 && header && (len_u32 >= 4 || gc_verify_env_cached == 0) &&
        compact_numeric_segment_layout(gc_object_layout(heap, header), elem_size, elem_tag)) {
        uint8_t *dst = (uint8_t *)(header + 1) + GC_ARRAY_DATA_OFFSET + (size_t)arr_off_u32 * elem_size;
        memcpy(dst, p, (size_t)total_bytes);
        gc_access_verify(heap, "array_data_init");
        return;
    }
    for (uint32_t i = 0; i < len_u32; i++) {
        GcSlot value = decode_array_elem_from_bytes(p + (size_t)i * elem_size, elem_tag);
        gc_heap_array_set_wide(heap, gc_ref, (int32_t)(arr_off_u32 + i), value);
    }
}

// array.init_elem - Initialize array region from element segment
static void WASMOON_GUEST_ABI gc_array_init_elem_impl(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t elem_idx,
    int64_t array_ref,
    int64_t arr_offset,
    int64_t elem_offset,
    int64_t length
) {
    (void)type_idx;
    if (!ctx || !ctx_gc_heap(ctx)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }
    GcHeap *heap = (GcHeap *)ctx_gc_heap(ctx);

    // Bounds check element segment index
    if (elem_idx < 0 || elem_idx >= segment_count(ctx_segments_state(ctx)->elem_segments)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    // If segment is dropped, only length=0 is valid
    uint32_t len_u32 = (uint32_t)length;
    uint32_t elem_off_u32 = (uint32_t)elem_offset;
    uint32_t arr_off_u32 = (uint32_t)arr_offset;
    if (array_ref == 0) {
        jit_trap_result(WASMOON_TRAP_NULL_REFERENCE);
        return;
    }

    int32_t gc_ref = gc_heap_ref_id(heap, array_ref);
    int32_t array_len = gc_heap_array_len(heap, gc_ref);
    if (!segment_range_fits((uint64_t)array_len, arr_off_u32, len_u32)) {
        jit_trap_result(WASMOON_TRAP_ARRAY_BOUNDS);
        return;
    }

    // Get segment data
    int64_t *seg_data = ctx_segments_state(ctx)->elem_segments ? ctx_segments_state(ctx)->elem_segments[elem_idx] : NULL;
    size_t seg_size = elem_is_dropped(ctx, elem_idx) ? 0 : (size_t)Moonbit_array_length(seg_data) / 2;

    // Bounds check source range in segment
    if (!segment_range_fits(seg_size, elem_off_u32, len_u32)) {
        jit_trap_result(WASMOON_TRAP_TABLE_BOUNDS);
        return;
    }

    for (uint32_t i = 0; i < len_u32; i++) {
        int64_t seg_off = ((int64_t)elem_off_u32 + (int64_t)i) * 2;
        int64_t v = seg_data[seg_off];
        gc_heap_array_set(heap, gc_ref, (int32_t)(arr_off_u32 + i), v);
    }
}

// GC array segment function pointer getters
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_data_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_new_data_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_elem_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_new_elem_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_init_data_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_init_data_impl);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_init_elem_ptr(void) {
    return WASMOON_GUEST_ADDRESS(gc_array_init_elem_impl);
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(data_drop_impl);
WASMOON_DEFINE_GUEST_TARGET(elem_drop_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_init_data_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_init_elem_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_new_data_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_new_elem_impl);
WASMOON_DEFINE_GUEST_TARGET(memory_init_impl);
WASMOON_DEFINE_GUEST_TARGET(table_copy_impl);
WASMOON_DEFINE_GUEST_TARGET(table_fill_impl);
WASMOON_DEFINE_GUEST_TARGET(table_get_impl);
WASMOON_DEFINE_GUEST_TARGET(table_call_target_impl);
WASMOON_DEFINE_GUEST_TARGET(funcref_call_target_impl);
WASMOON_DEFINE_GUEST_TARGET(function_reference_impl);
WASMOON_DEFINE_GUEST_TARGET(table_init_impl);
#endif
