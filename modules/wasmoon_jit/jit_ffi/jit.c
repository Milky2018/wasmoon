// Copyright 2025
// JIT runtime FFI exports for MoonBit
// This file only contains MOONBIT_FFI_EXPORT functions that wrap internal implementations

#include "jit_internal.h"

// ============ Hostcall Bridge (JIT -> Host) ============
// Thread-local scratch for the currently executing hostcall.
// This is read by the MoonBit dispatcher via FFI getters.
static __thread int32_t g_hostcall_func_idx = -1;
static __thread int64_t g_hostcall_values_ptr = 0;
static __thread int32_t g_hostcall_num_args = 0;
static __thread int32_t g_hostcall_num_results = 0;

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_host_target_arch(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return 1;
#elif defined(__aarch64__) || defined(_M_ARM64)
    return 2;
#else
    return 0;
#endif
}

// ============ Trap Handling FFI Exports ============

MOONBIT_FFI_EXPORT int wasmoon_jit_get_trap_code(void) {
    return (int)g_trap_code;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_trap(void) {
    g_trap_code = 0;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_get_trap_signal(void) {
    return (int)g_trap_signal;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_pc(void) {
    return (int64_t)g_trap_pc;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_lr(void) {
    return (int64_t)g_trap_lr;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_fp(void) {
    return (int64_t)g_trap_fp;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_frame_lr(void) {
    return (int64_t)g_trap_frame_lr;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_fault_addr(void) {
    return (int64_t)g_trap_fault_addr;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_xreg(int idx) {
    switch (idx) {
        case 0: return (int64_t)g_trap_x0;
        case 1: return (int64_t)g_trap_x1;
        case 2: return (int64_t)g_trap_x2;
        case 3: return (int64_t)g_trap_x3;
        case 6: return (int64_t)g_trap_x6;
        case 7: return (int64_t)g_trap_x7;
        case 8: return (int64_t)g_trap_x8;
        case 9: return (int64_t)g_trap_x9;
        case 10: return (int64_t)g_trap_x10;
        case 11: return (int64_t)g_trap_x11;
        case 15: return (int64_t)g_trap_x15;
        default: return 0;
    }
}

// ============ Hostcall Callback Registration ============

typedef int32_t (*hostcall_callback_fn)(void *closure);

static void clear_hostcall_callback(jit_context_t *ctx) {
    if (!ctx) return;
    if (ctx->hostcall_callback_data) {
        moonbit_decref(ctx->hostcall_callback_data);
        ctx->hostcall_callback_data = NULL;
    }
    ctx->hostcall_callback = NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_hostcall_callback(
    int64_t ctx_ptr,
    hostcall_callback_fn callback,
    void *closure
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_hostcall_callback(ctx);
    ctx->hostcall_callback = (void *)callback;
    if (closure) moonbit_incref(closure);
    ctx->hostcall_callback_data = closure;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_hostcall_callback(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_hostcall_callback(ctx);
}

// ============ Hostcall Execution ============

// Called by JIT-generated trampolines (C calling convention).
// On error, sets g_trap_code and longjmps back to the JIT entrypoint.
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_hostcall(
    jit_context_t *ctx,
    int32_t func_idx,
    int64_t values_ptr,
    int32_t num_args,
    int32_t num_results
) {
    if (!ctx || !ctx->hostcall_callback) {
        g_trap_code = 3; // unreachable
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return (int32_t)g_trap_code;
    }
    // Defensive: hostcall trampolines pass a pointer into the active WASM stack.
    // If ABI bugs pass an invalid pointer, the MoonBit dispatcher may scribble
    // over unrelated memory and corrupt the heap.
    if (ctx->wasm_stack_base && ctx->wasm_stack_top) {
        uintptr_t base = (uintptr_t)ctx->wasm_stack_base;
        uintptr_t top = (uintptr_t)ctx->wasm_stack_top;
        uintptr_t ptr = (uintptr_t)values_ptr;
        // Each slot is 8 bytes; `num_args`/`num_results` are already slot counts
        // (v128 uses 2 slots in the trampoline).
        uintptr_t bytes = (uintptr_t)(num_args + num_results) * 8u;
        if (ptr < base || ptr + bytes > top) {
            g_trap_code = 3; // unreachable
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return (int32_t)g_trap_code;
        }
    }

    g_hostcall_func_idx = func_idx;
    g_hostcall_values_ptr = values_ptr;
    g_hostcall_num_args = num_args;
    g_hostcall_num_results = num_results;

    hostcall_callback_fn cb = (hostcall_callback_fn)ctx->hostcall_callback;
    int32_t trap = cb(ctx->hostcall_callback_data);
    if (trap != 0) {
        g_trap_code = trap;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    }
    return trap;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_hostcall_ptr(void) {
    return (int64_t)wasmoon_jit_hostcall;
}

// ============ Cooperative Cancellation ============

typedef int32_t (*cancellation_callback_fn)(void *closure);

static void clear_cancellation_callback(jit_context_t *ctx) {
    if (!ctx) return;
    if (ctx->cancellation_callback_data) {
        moonbit_decref(ctx->cancellation_callback_data);
        ctx->cancellation_callback_data = NULL;
    }
    ctx->cancellation_callback = NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_cancellation_callback(
    int64_t ctx_ptr,
    cancellation_callback_fn callback,
    void *closure
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_cancellation_callback(ctx);
    ctx->cancellation_callback = (void *)callback;
    if (closure) moonbit_incref(closure);
    ctx->cancellation_callback_data = closure;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_cancellation_callback(int64_t ctx_ptr) {
    clear_cancellation_callback((jit_context_t *)ctx_ptr);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_cancel_poll(jit_context_t *ctx) {
    if (!ctx || !ctx->cancellation_callback) return 0;
    cancellation_callback_fn cb =
        (cancellation_callback_fn)ctx->cancellation_callback;
    if (cb(ctx->cancellation_callback_data) != 0) {
        g_trap_code = 11;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 11;
    }
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_cancel_poll_ptr(void) {
    return (int64_t)wasmoon_jit_cancel_poll;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_get_hostcall_func_idx(void) {
    return g_hostcall_func_idx;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_hostcall_values_ptr(void) {
    return g_hostcall_values_ptr;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_get_hostcall_num_args(void) {
    return g_hostcall_num_args;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_get_hostcall_num_results(void) {
    return g_hostcall_num_results;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_get_trap_brk_imm(void) {
    return (int)g_trap_brk_imm;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_get_trap_func_idx(void) {
    return (int)g_trap_func_idx;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_wasm_stack_base(void) {
    return (int64_t)g_trap_wasm_stack_base;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_wasm_stack_top(void) {
    return (int64_t)g_trap_wasm_stack_top;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_get_trap_frame_count(void) {
    return g_trap_frame_count;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_frame_pc(int idx) {
    if (idx >= 0 && idx < g_trap_frame_count) {
        return (int64_t)g_trap_frames_pc[idx];
    }
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_trap_frame_fp(int idx) {
    if (idx >= 0 && idx < g_trap_frame_count) {
        return (int64_t)g_trap_frames_fp[idx];
    }
    return 0;
}

// ============ Context Management FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_context(int func_count) {
    return (int64_t)alloc_context_internal(func_count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_func(int64_t ctx_ptr, int idx, int64_t func_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && idx >= 0 && idx < ctx->func_count) {
        ctx->func_table[idx] = (void *)func_ptr;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_memory(int64_t ctx_ptr, int64_t mem0_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        wasmoon_memory_t *new_mem0 = (wasmoon_memory_t *)mem0_ptr;

        // If the pointer is unchanged, keep existing ownership state.
        if (ctx->memory0 == new_mem0) {
            ctx_refresh_memory0_fast_fields(ctx);
            return;
        }

        // If we previously owned memory0 (allocated via ctx_alloc_guarded_memory), free it.
        if (ctx->owns_memory0 && ctx->memory0) {
            wasmoon_jit_free_memory_desc((int64_t)ctx->memory0);
        }

        ctx->memory0 = new_mem0;
        ctx->owns_memory0 = 0;
        ctx_refresh_memory0_fast_fields(ctx);
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_globals(int64_t ctx_ptr, int64_t globals_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        ctx->globals = (void *)globals_ptr;
    }
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_func_table(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return ctx ? (int64_t)ctx->func_table : 0;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_ctx_get_func_count(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return ctx ? ctx->func_count : 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_table_ptr(int64_t ctx_ptr, int table_idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_idx < 0 || table_idx >= ctx->table_count || !ctx->tables) {
        return 0;
    }
    return (int64_t)ctx->tables[table_idx];
}

MOONBIT_FFI_EXPORT int wasmoon_jit_ctx_get_table_size(int64_t ctx_ptr, int table_idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_idx < 0 || table_idx >= ctx->table_count) {
        return 0;
    }
    if (table_idx == 0) {
        return (int)ctx->table0_elements;
    }
    if (!ctx->table_sizes) {
        return 0;
    }
    return (int)ctx->table_sizes[table_idx];
}

MOONBIT_FFI_EXPORT int wasmoon_jit_ctx_alloc_indirect_table(int64_t ctx_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || count <= 0) return 0;

    // Only free if we own the current table0_base
    if (ctx->table0_base && ctx->owns_indirect_table) {
        free(ctx->table0_base);
    }

    // Allocate 2 slots per entry: func_ptr and type_idx
    ctx->table0_base = (void **)calloc(count * 2, sizeof(void *));
    if (!ctx->table0_base) {
        ctx->table0_elements = 0;
        ctx->owns_indirect_table = 0;
        return 0;
    }
    // Initialize type indices to -1 (uninitialized marker)
    for (int i = 0; i < count; i++) {
        ctx->table0_base[i * 2 + 1] = (void*)(intptr_t)(-1);
    }
    ctx->table0_elements = count;
    ctx->owns_indirect_table = 1;
    return 1;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_indirect(int64_t ctx_ptr, int table_idx, int func_idx, int type_idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx->table0_base &&
        table_idx >= 0 && (size_t)table_idx < ctx->table0_elements &&
        func_idx >= 0 && func_idx < ctx->func_count) {
        ctx->table0_base[table_idx * 2] = ctx->func_table[func_idx];
        ctx->table0_base[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
    }
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_indirect_table(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx->table0_base) {
        return (int64_t)ctx->table0_base;
    }
    return ctx ? (int64_t)ctx->func_table : 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_context(int64_t ctx_ptr) {
    free_context_internal((jit_context_t *)ctx_ptr);
}

// ============ GC-managed JITContext ============

static void finalize_jit_context(void *self) {
    int64_t *ptr = (int64_t *)self;
    if (*ptr != 0) {
        wasmoon_jit_free_context(*ptr);
        *ptr = 0;
    }
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_context_managed(int func_count) {
    int64_t ctx_ptr = wasmoon_jit_alloc_context(func_count);
    if (ctx_ptr == 0) {
        return NULL;
    }

    int64_t *payload = (int64_t *)moonbit_make_external_object(finalize_jit_context, sizeof(int64_t));
    if (!payload) {
        wasmoon_jit_free_context(ctx_ptr);
        return NULL;
    }

    *payload = ctx_ptr;
    return payload;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_context_ptr(void *jit_context) {
    if (!jit_context) return 0;
    return *(int64_t *)jit_context;
}

// ============ Shared Indirect Table Support ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_shared_indirect_table(int count) {
    if (count <= 0) return 0;

    void **table = (void **)calloc(count * 2, sizeof(void *));
    if (!table) return 0;

    for (int i = 0; i < count; i++) {
        table[i * 2] = (void*)(intptr_t)(0);
        table[i * 2 + 1] = (void*)(intptr_t)(-1);
    }

    return (int64_t)table;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_shared_indirect_table(int64_t table_ptr) {
    void **table = (void **)table_ptr;
    if (table) {
        free(table);
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_shared_table_set(int64_t table_ptr, int table_idx, int64_t func_ptr, int type_idx) {
    void **table = (void **)table_ptr;
    if (table && table_idx >= 0) {
        table[table_idx * 2] = (void *)func_ptr;
        table[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
    }
}

// ============ Table Operations ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_table_grow(
    jit_context_t *ctx,
    int32_t table_idx,
    int64_t delta,
    int64_t init_value
) {
    return table_grow_ctx_internal(ctx, table_idx, delta, init_value);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_grow_ptr(void) {
    return (int64_t)wasmoon_jit_table_grow;
}

// ============ Multi-Memory Operations (with memidx) ============

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_memory_grow(
    jit_context_t *ctx,
    int32_t memidx,
    int64_t delta,
    int32_t max_pages
) {
    return memory_grow_indexed_internal(ctx, memidx, delta, max_pages);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_memory_size(jit_context_t *ctx, int32_t memidx) {
    return memory_size_indexed_internal(ctx, memidx);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_memory_fill(
    jit_context_t *ctx,
    int32_t memidx,
    int32_t dst,
    int32_t val,
    int32_t size
) {
    memory_fill_indexed_internal(ctx, memidx, dst, val, size);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_memory_copy(
    jit_context_t *ctx,
    int32_t dst_memidx,
    int32_t src_memidx,
    int32_t dst,
    int32_t src,
    int32_t size
) {
    memory_copy_indexed_internal(ctx, dst_memidx, src_memidx, dst, src, size);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_grow_ptr(void) {
    return (int64_t)memory_grow_indexed_internal;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_ptr(void) {
    return (int64_t)memory_size_indexed_internal;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_fill_ptr(void) {
    return (int64_t)memory_fill_indexed_internal;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_copy_ptr(void) {
    return (int64_t)memory_copy_indexed_internal;
}

// ============ Integer div/rem helpers ============
//
// These helpers are used as a bootstrap on x86_64 to get the JIT backend
// working before implementing full idiv lowering/encoding.
//
// NOTE: For signed remainder, INT_MIN % -1 is undefined behavior in C, but is
// well-defined in WebAssembly (result 0). We special-case b == -1 to avoid UB.

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_i32_sdiv(int32_t a, int32_t b) {
    return a / b;
}

MOONBIT_FFI_EXPORT uint32_t wasmoon_jit_i32_udiv(uint32_t a, uint32_t b) {
    return a / b;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_i32_srem(int32_t a, int32_t b) {
    if (b == -1) return 0;
    return a % b;
}

MOONBIT_FFI_EXPORT uint32_t wasmoon_jit_i32_urem(uint32_t a, uint32_t b) {
    return a % b;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_i64_sdiv(int64_t a, int64_t b) {
    return a / b;
}

MOONBIT_FFI_EXPORT uint64_t wasmoon_jit_i64_udiv(uint64_t a, uint64_t b) {
    return a / b;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_i64_srem(int64_t a, int64_t b) {
    if (b == -1) return 0;
    return a % b;
}

MOONBIT_FFI_EXPORT uint64_t wasmoon_jit_i64_urem(uint64_t a, uint64_t b) {
    return a % b;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i32_sdiv_ptr(void) {
    return (int64_t)wasmoon_jit_i32_sdiv;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i32_udiv_ptr(void) {
    return (int64_t)wasmoon_jit_i32_udiv;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i32_srem_ptr(void) {
    return (int64_t)wasmoon_jit_i32_srem;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i32_urem_ptr(void) {
    return (int64_t)wasmoon_jit_i32_urem;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i64_sdiv_ptr(void) {
    return (int64_t)wasmoon_jit_i64_sdiv;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i64_udiv_ptr(void) {
    return (int64_t)wasmoon_jit_i64_udiv;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i64_srem_ptr(void) {
    return (int64_t)wasmoon_jit_i64_srem;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_i64_urem_ptr(void) {
    return (int64_t)wasmoon_jit_i64_urem;
}

// ============ Multi-Memory Array Setup ============

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_memory_pointers(
    int64_t ctx_ptr,
    int64_t *memory_ptrs,
    int memory_count
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || memory_count <= 0 || !memory_ptrs) return;

    wasmoon_memory_t *old_mem0 = ctx->memory0;
    int old_owns_mem0 = ctx->owns_memory0;
    wasmoon_memory_t *new_mem0 = (wasmoon_memory_t *)memory_ptrs[0];

    // Free existing array
    if (ctx->memories) {
        free(ctx->memories);
        ctx->memories = NULL;
    }

    // If we previously owned memory0 (allocated via ctx_alloc_guarded_memory), free it
    // unless the new memory0 pointer is the same.
    if (old_owns_mem0 && old_mem0 && old_mem0 != new_mem0) {
        wasmoon_jit_free_memory_desc((int64_t)old_mem0);
        old_mem0 = NULL;
        old_owns_mem0 = 0;
    }

    ctx->memory_count = 0;
    ctx->memory0 = NULL;
    ctx->owns_memory0 = (old_owns_mem0 && old_mem0 == new_mem0) ? 1 : 0;
    ctx_refresh_memory0_fast_fields(ctx);

    // Allocate array to hold memory pointers
    ctx->memories = (wasmoon_memory_t **)calloc(memory_count, sizeof(wasmoon_memory_t *));
    if (!ctx->memories) return;

    // Copy pointers
    for (int i = 0; i < memory_count; i++) {
        ctx->memories[i] = (wasmoon_memory_t *)memory_ptrs[i];
    }
    ctx->memory_count = memory_count;

    // Set memory 0 fast path
    if (memory_count > 0) {
        ctx->memory0 = ctx->memories[0];
    }
    ctx_refresh_memory0_fast_fields(ctx);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_use_shared_table(int64_t ctx_ptr, int64_t shared_table_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    if (ctx->table0_base && ctx->owns_indirect_table) {
        free(ctx->table0_base);
    }

    ctx->table0_base = (void **)shared_table_ptr;
    ctx->table0_elements = count;
    ctx->owns_indirect_table = 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_table_pointers(
    int64_t ctx_ptr,
    int64_t *table_ptrs,
    int32_t *table_sizes,
    int32_t *table_max_sizes,
    int table_count
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_count <= 0 || !table_ptrs) return;

    // Free existing arrays
    if (ctx->tables) {
        free(ctx->tables);
        ctx->tables = NULL;
    }
    if (ctx->table_sizes) {
        free(ctx->table_sizes);
        ctx->table_sizes = NULL;
    }
    if (ctx->table_max_sizes) {
        free(ctx->table_max_sizes);
        ctx->table_max_sizes = NULL;
    }
    ctx->table_count = 0;

    // Allocate arrays
    ctx->tables = (void ***)calloc(table_count, sizeof(void **));
    if (!ctx->tables) return;

    ctx->table_sizes = (size_t *)calloc(table_count, sizeof(size_t));
    if (!ctx->table_sizes) {
        free(ctx->tables);
        ctx->tables = NULL;
        return;
    }

    ctx->table_max_sizes = (size_t *)calloc(table_count, sizeof(size_t));
    if (!ctx->table_max_sizes) {
        free(ctx->tables);
        free(ctx->table_sizes);
        ctx->tables = NULL;
        ctx->table_sizes = NULL;
        return;
    }

    // Copy table data
    for (int i = 0; i < table_count; i++) {
        ctx->tables[i] = (void **)table_ptrs[i];
        if (table_sizes) {
            ctx->table_sizes[i] = (size_t)table_sizes[i];
        }
        if (table_max_sizes) {
            ctx->table_max_sizes[i] = (table_max_sizes[i] < 0) ? SIZE_MAX : (size_t)table_max_sizes[i];
        } else {
            ctx->table_max_sizes[i] = SIZE_MAX;
        }
    }
    ctx->table_count = table_count;

    // Set table0 fast path
    if (table_count > 0 && table_ptrs[0] != 0) {
        ctx->table0_base = (void **)table_ptrs[0];
        ctx->owns_indirect_table = 0;
        if (table_sizes) {
            ctx->table0_elements = table_sizes[0];
        }
    }
}

// ============ Trampoline-based Call ============

typedef int (*entry_trampoline_fn)(jit_context_t *vmctx, int64_t *values_vec, void *func_ptr);

#if defined(__x86_64__) || defined(_M_X64)
// ABI-safe wrapper implemented in `trampoline_call_x86_64.S`.
// JIT-generated entry trampolines intentionally use reserved callee-saved
// registers as pinned VMContext/cache registers and may clobber them.
// Calling them directly from C would violate SysV guarantees and corrupt the
// caller's state.
extern int wasmoon_call_entry_trampoline(
    void *trampoline_ptr,
    void *vmctx,
    void *values_vec,
    void *func_ptr
);
#endif

// Global pointer to current JIT context for guard page detection in signal handler
// This is set before JIT execution and cleared after
static __thread jit_context_t *g_current_jit_context = NULL;

jit_context_t *get_current_jit_context(void) {
    return g_current_jit_context;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_call_trampoline(
    int64_t trampoline_ptr,
    int64_t ctx_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
) {
    (void)values_len;

    if (!trampoline_ptr || !ctx_ptr || !func_ptr) return -1;

    install_trap_handler();
    g_trap_code = 0;
    g_trap_signal = 0;
    g_trap_pc = 0;
    g_trap_lr = 0;
    g_trap_frame_lr = 0;
    g_trap_fault_addr = 0;
    g_trap_brk_imm = -1;
    g_trap_func_idx = -1;
    g_trap_active = 1;

    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    ctx_refresh_memory0_fast_fields(ctx);
    exception_reset_context_state(ctx);
    g_current_jit_context = ctx;  // Set for guard page detection
    g_trap_wasm_stack_base = (uintptr_t)ctx->wasm_stack_base;
    g_trap_wasm_stack_top = (uintptr_t)ctx->wasm_stack_top;

    if (sigsetjmp(g_trap_jmp_buf, 1) != 0) {
        g_trap_active = 0;
        exception_reset_context_state(ctx);
        g_current_jit_context = NULL;
        g_trap_wasm_stack_base = 0;
        g_trap_wasm_stack_top = 0;
        return (int)g_trap_code;
    }

    int result;
#if defined(__x86_64__) || defined(_M_X64)
    result = wasmoon_call_entry_trampoline(
        (void *)trampoline_ptr,
        ctx,
        values_vec,
        (void *)func_ptr
    );
#else
    entry_trampoline_fn trampoline = (entry_trampoline_fn)trampoline_ptr;
    result = trampoline(ctx, values_vec, (void *)func_ptr);
#endif

    g_trap_active = 0;
    exception_reset_context_state(ctx);
    g_current_jit_context = NULL;
    g_trap_wasm_stack_base = 0;
    g_trap_wasm_stack_top = 0;

    if (g_trap_code != 0) {
        return (int)g_trap_code;
    }

    return result;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_call_trampoline_managed(
    void *jit_context,
    int64_t trampoline_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
) {
    if (!jit_context) return -1;
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    return wasmoon_jit_call_trampoline(trampoline_ptr, ctx_ptr, func_ptr, values_vec, values_len);
}

// ============ Stack-Switching Trampoline Call ============

// External assembly function for stack switching (from stack_switch_aarch64.S)
#if defined(__aarch64__) || defined(_M_ARM64) || defined(__x86_64__) || defined(_M_X64)
extern int stack_switch_call(
    void *wasm_stack_top,
    void *trampoline_ptr,
    void *vmctx,
    void *values_vec,
    void *func_ptr
);
#endif

MOONBIT_FFI_EXPORT int wasmoon_jit_call_with_stack_switch(
    int64_t trampoline_ptr,
    int64_t ctx_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
) {
    (void)values_len;

    if (!trampoline_ptr || !ctx_ptr || !func_ptr) return -1;

    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    ctx_refresh_memory0_fast_fields(ctx);

    // Check if WASM stack is allocated
    if (!ctx->wasm_stack_top) {
        // Fall back to regular call if no WASM stack
        return wasmoon_jit_call_trampoline(trampoline_ptr, ctx_ptr, func_ptr, values_vec, values_len);
    }

#if defined(__aarch64__) || defined(_M_ARM64) || defined(__x86_64__) || defined(_M_X64)
    install_trap_handler();
    g_trap_code = 0;
    g_trap_signal = 0;
    g_trap_pc = 0;
    g_trap_lr = 0;
    g_trap_frame_lr = 0;
    g_trap_fault_addr = 0;
    g_trap_brk_imm = -1;
    g_trap_func_idx = -1;
    g_trap_active = 1;
    g_current_jit_context = ctx;  // Set for guard page detection
    exception_reset_context_state(ctx);
    g_trap_wasm_stack_base = (uintptr_t)ctx->wasm_stack_base;
    g_trap_wasm_stack_top = (uintptr_t)ctx->wasm_stack_top;

    if (sigsetjmp(g_trap_jmp_buf, 1) != 0) {
        g_trap_active = 0;
        exception_reset_context_state(ctx);
        g_current_jit_context = NULL;
        g_trap_wasm_stack_base = 0;
        g_trap_wasm_stack_top = 0;
        return (int)g_trap_code;
    }

    // Call using stack-switching assembly
    int result = stack_switch_call(
        ctx->wasm_stack_top,
        (void *)trampoline_ptr,
        ctx,
        values_vec,
        (void *)func_ptr
    );

    g_trap_active = 0;
    exception_reset_context_state(ctx);
    g_current_jit_context = NULL;
    g_trap_wasm_stack_base = 0;
    g_trap_wasm_stack_top = 0;

    if (g_trap_code != 0) {
        return (int)g_trap_code;
    }

    return result;
#else
    // On targets without a stack-switch helper, fall back to regular call.
    return wasmoon_jit_call_trampoline(trampoline_ptr, ctx_ptr, func_ptr, values_vec, values_len);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_jit_call_with_stack_switch_managed(
    void *jit_context,
    int64_t trampoline_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
) {
    if (!jit_context) return -1;
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    return wasmoon_jit_call_with_stack_switch(trampoline_ptr, ctx_ptr, func_ptr, values_vec, values_len);
}

// ============ Spectest Trampolines ============

static void spectest_print_impl(int64_t func_table, int64_t mem_base) {
    (void)func_table;
    (void)mem_base;
}

static void spectest_print_i32_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

static void spectest_print_i64_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

static void spectest_print_f32_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

static void spectest_print_f64_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

static void spectest_print_i32_f32_impl(int64_t func_table, int64_t mem_base, int64_t arg0, int64_t arg1) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
    (void)arg1;
}

static void spectest_print_f64_f64_impl(int64_t func_table, int64_t mem_base, int64_t arg0, int64_t arg1) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
    (void)arg1;
}

static void spectest_print_char_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    putchar((int)arg0);
    fflush(stdout);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_ptr(void) {
    return (int64_t)spectest_print_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_i32_ptr(void) {
    return (int64_t)spectest_print_i32_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_i64_ptr(void) {
    return (int64_t)spectest_print_i64_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_f32_ptr(void) {
    return (int64_t)spectest_print_f32_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_f64_ptr(void) {
    return (int64_t)spectest_print_f64_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_i32_f32_ptr(void) {
    return (int64_t)spectest_print_i32_f32_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_f64_f64_ptr(void) {
    return (int64_t)spectest_print_f64_f64_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_char_ptr(void) {
    return (int64_t)spectest_print_char_impl;
}

// ============ Linear Memory Allocation FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_memory(int64_t size) {
    if (size <= 0) return 0;
    void *mem = calloc(1, (size_t)size);
    return (int64_t)mem;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_memory_desc(
    int64_t size_bytes,
    int32_t max_pages,
    int32_t is_memory64,
    int32_t page_size_log2,
    int32_t is_shared
) {
    if (size_bytes < 0) return 0;
    wasmoon_memory_t *mem = (wasmoon_memory_t *)calloc(1, sizeof(wasmoon_memory_t));
    if (!mem) return 0;

    if (size_bytes > 0) {
        uint8_t *base = (uint8_t *)calloc(1, (size_t)size_bytes);
        if (!base) {
            free(mem);
            return 0;
        }
        mem->base = base;
        atomic_store_explicit(&mem->current_length, (size_t)size_bytes, memory_order_relaxed);
    } else {
        mem->base = NULL;
        atomic_store_explicit(&mem->current_length, 0, memory_order_relaxed);
    }

    mem->max_pages = (max_pages < 0) ? SIZE_MAX : (size_t)max_pages;
    mem->is_memory64 = (is_memory64 != 0);
    mem->page_size_log2 = page_size_log2;
    mem->is_shared = (is_shared != 0);
    mem->is_guarded = 0;
    return (int64_t)mem;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_memory_desc(int64_t mem_ptr) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_ptr;
    if (!mem) return;

    if (mem->is_guarded) {
        if (mem->alloc_base) {
#ifdef _WIN32
            VirtualFree(mem->alloc_base, 0, MEM_RELEASE);
#else
            munmap(mem->alloc_base, mem->alloc_size);
#endif
        }
    } else {
        if (mem->base) {
            free(mem->base);
        }
    }

    free(mem);
}

// Allocate guarded memory into a standalone descriptor (store-owned).
// Returns `wasmoon_memory_t*` on success, 0 on failure.
extern uint8_t *alloc_guarded_memory_external(wasmoon_memory_t *memory, size_t initial_size, size_t max_size);

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_guarded_memory_desc(int64_t initial_pages, int64_t max_pages) {
    // Guarded memory is used for memory32 bounds-check elimination.
    // Only supported for 64KiB pages.
    if (initial_pages < 0 || initial_pages > 65536) {
        return 0;
    }
    if (max_pages > 65536) {
        max_pages = 65536;
    }

    size_t initial_size = (size_t)initial_pages * WASM_PAGE_SIZE;
    size_t max_size = (max_pages < 0) ? 0 : (size_t)max_pages * WASM_PAGE_SIZE;

    wasmoon_memory_t *memory = (wasmoon_memory_t *)calloc(1, sizeof(wasmoon_memory_t));
    if (!memory) {
        return 0;
    }

    memory->max_pages = (max_pages < 0) ? SIZE_MAX : (size_t)max_pages;
    memory->is_memory64 = 0;
    memory->page_size_log2 = 16;
    memory->is_shared = 0;

    uint8_t *base = alloc_guarded_memory_external(memory, initial_size, max_size);
    if (!base && initial_size > 0) {
        free(memory);
        return 0;
    }

    return (int64_t)memory;
}

// Allocate guarded memory directly into JIT context
// This allocates memory using mmap with guard pages for bounds check elimination
// Returns memory pointer on success, 0 on failure

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_alloc_guarded_memory(
    int64_t ctx_ptr,
    int64_t initial_pages,
    int64_t max_pages
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) {
        return 0;
    }

    // Guarded memory is used for memory32 bounds-check elimination.
    // Clamp to the memory32 architectural limit (4GB = 65536 pages).
    if (initial_pages < 0 || initial_pages > 65536) {
        return 0;
    }
    if (max_pages > 65536) {
        max_pages = 65536;
    }

    // Convert pages to bytes (WASM page = 64KB)
    size_t initial_size = (size_t)initial_pages * WASM_PAGE_SIZE;
    // max_pages is currently unused by alloc_guarded_memory (fixed reservation),
    // but keep the parameter for future extensions.
    size_t max_size = (max_pages < 0) ? 0 : (size_t)max_pages * WASM_PAGE_SIZE;

    // If we previously owned memory0 (allocated via ctx_alloc_guarded_memory), free it.
    if (ctx->owns_memory0 && ctx->memory0) {
        wasmoon_jit_free_memory_desc((int64_t)ctx->memory0);
        ctx->memory0 = NULL;
        ctx->owns_memory0 = 0;
        ctx_refresh_memory0_fast_fields(ctx);
    }

    wasmoon_memory_t *memory = (wasmoon_memory_t *)calloc(1, sizeof(wasmoon_memory_t));
    if (!memory) {
        return 0;
    }
    memory->max_pages = (max_pages < 0) ? SIZE_MAX : (size_t)max_pages;
    memory->is_memory64 = 0;
    memory->page_size_log2 = 16;
    memory->is_shared = 0;

    uint8_t *base = alloc_guarded_memory_external(memory, initial_size, max_size);

    if (!base && initial_size > 0) {
        free(memory);
        return 0;
    }

    // Set memory0 in context
    ctx->memory0 = memory;
    ctx->owns_memory0 = 1;
    ctx_refresh_memory0_fast_fields(ctx);

    return (int64_t)memory;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_memory(int64_t mem_ptr) {
    if (mem_ptr) {
        free((void *)mem_ptr);
    }
}

MOONBIT_FFI_EXPORT int wasmoon_jit_memory_init(int64_t mem_ptr, int64_t offset, moonbit_bytes_t data, int size) {
    if (!mem_ptr || !data || size <= 0) return -1;
    uint8_t *mem = (uint8_t *)mem_ptr;
    memcpy(mem + offset, data, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_memory_init_bytes(int64_t mem_ptr, int64_t offset, moonbit_bytes_t data, int size) {
    return wasmoon_jit_memory_init(mem_ptr, offset, data, size);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_memory_read(int64_t mem_ptr, int64_t offset, moonbit_bytes_t out, int size) {
    if (!mem_ptr || !out || size <= 0) return -1;
    uint8_t *mem = (uint8_t *)mem_ptr;
    memcpy(out, mem + offset, (size_t)size);
    return 0;
}

// ============ Memory Descriptor Helpers (runtime + JIT sharing) ============

MOONBIT_FFI_EXPORT int64_t wasmoon_mem_desc_get_base(int64_t mem_desc_ptr) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    return (int64_t)memory_base_desc_internal(mem);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_mem_desc_get_len(int64_t mem_desc_ptr) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    return memory_len_desc_internal(mem);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_mem_desc_grow(int64_t mem_desc_ptr, int32_t delta, int32_t max_pages) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    return memory_grow_desc_internal(mem, delta, max_pages);
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_read(int64_t mem_desc_ptr, int64_t offset, moonbit_bytes_t out, int size) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    if (!mem || !mem->base || !out || size <= 0) return -1;
    memcpy(out, mem->base + offset, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_write(int64_t mem_desc_ptr, int64_t offset, moonbit_bytes_t data, int size) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    if (!mem || !mem->base || !data || size <= 0) return -1;
    memcpy(mem->base + offset, data, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_write_bytes(int64_t mem_desc_ptr, int64_t offset, moonbit_bytes_t data, int size) {
    return wasmoon_mem_desc_write(mem_desc_ptr, offset, data, size);
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_memmove(int64_t mem_desc_ptr, int64_t dst, int64_t src, int size) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    if (!mem || !mem->base || size <= 0) return -1;
    memmove(mem->base + dst, mem->base + src, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_mem_desc_memset(int64_t mem_desc_ptr, int64_t dst, int32_t val, int size) {
    wasmoon_memory_t *mem = (wasmoon_memory_t *)mem_desc_ptr;
    if (!mem || !mem->base || size <= 0) return -1;
    memset(mem->base + dst, val & 0xFF, (size_t)size);
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_memory_ptr(int64_t ctx_ptr, int memidx) {
    if (!ctx_ptr || memidx < 0) return 0;
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;

    if (memidx == 0) {
        return ctx->memory0_base ? (int64_t)ctx->memory0_base : 0;
    }

    if (ctx->memories && ctx->memory_count > 0 && memidx < ctx->memory_count) {
        wasmoon_memory_t *mem = ctx->memories[memidx];
        return (mem && mem->base) ? (int64_t)mem->base : 0;
    }

    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_memory_size(int64_t ctx_ptr, int memidx) {
    if (!ctx_ptr || memidx < 0) return 0;
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;

    if (memidx == 0) {
        return (int64_t)atomic_load_explicit(&ctx->memory0_size, memory_order_relaxed);
    }

    if (ctx->memories && ctx->memory_count > 0 && memidx < ctx->memory_count) {
        wasmoon_memory_t *mem = ctx->memories[memidx];
        return mem ? (int64_t)atomic_load_explicit(&mem->current_length, memory_order_relaxed) : 0;
    }

    return 0;
}

// ============ Executable Memory FFI Exports ============

typedef struct {
    int64_t ptr;
    int32_t size;
    int32_t finalized;
} managed_exec_code_t;

static void finalize_exec_code(void *self) {
    managed_exec_code_t *code = (managed_exec_code_t *)self;
    if (code->ptr != 0) {
        free_exec_internal(code->ptr);
        code->ptr = 0;
    }
}

static void *make_managed_exec_code(int64_t ptr, int size, int finalized) {
    managed_exec_code_t *payload = (managed_exec_code_t *)moonbit_make_external_object(
        finalize_exec_code,
        sizeof(managed_exec_code_t)
    );
    if (!payload) {
        free_exec_internal(ptr);
        return NULL;
    }
    payload->ptr = ptr;
    payload->size = size;
    payload->finalized = finalized;
    return payload;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_exec(int size) {
    return alloc_exec_internal(size);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_copy_code(int64_t dest, moonbit_bytes_t src, int size) {
    return copy_code_internal(dest, src, size);
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_exec_managed(moonbit_bytes_t code, int size) {
    if (size <= 0 || !code) {
        return NULL;
    }

    int64_t ptr = alloc_exec_internal(size);
    if (ptr == 0) {
        return NULL;
    }

    int result = copy_code_internal(ptr, code, size);
    if (result != 0) {
        free_exec_internal(ptr);
        return NULL;
    }

    return make_managed_exec_code(ptr, size, 1);
}

MOONBIT_FFI_EXPORT void *wasmoon_jit_stage_exec_managed(int size) {
    if (size <= 0) return NULL;
    int64_t ptr = alloc_exec_internal(size);
    if (ptr == 0) return NULL;
    return make_managed_exec_code(ptr, size, 0);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_finalize_exec_managed(
    void *exec_code,
    moonbit_bytes_t code,
    int size
) {
    if (!exec_code || !code) return -1;
    managed_exec_code_t *payload = (managed_exec_code_t *)exec_code;
    if (payload->ptr == 0 || payload->finalized || size != payload->size) return -1;
    if (copy_code_internal(payload->ptr, code, size) != 0) return -1;
    payload->finalized = 1;
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_release_exec_managed(void *exec_code) {
    if (!exec_code) return -1;
    managed_exec_code_t *payload = (managed_exec_code_t *)exec_code;
    if (payload->ptr == 0) return 0;
    if (free_exec_internal(payload->ptr) != 0) return -1;
    payload->ptr = 0;
    payload->size = 0;
    payload->finalized = 0;
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exec_code_ptr(void *exec_code) {
    if (!exec_code) return 0;
    return ((managed_exec_code_t *)exec_code)->ptr;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_exec_mapping_count(void) {
    return exec_block_count_internal();
}

// ============ Memory Read/Write Helpers ============

MOONBIT_FFI_EXPORT void wasmoon_jit_write_i64(int64_t addr, int64_t value) {
    if (addr == 0) return;
    if (copy_code_internal(addr, (const uint8_t *)&value, (int)sizeof(value)) != 0) {
        memcpy((void *)addr, &value, sizeof(value));
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_write_u32(int64_t addr, uint32_t value) {
    if (addr == 0) return;
    if (copy_code_internal(addr, (const uint8_t *)&value, (int)sizeof(value)) != 0) {
        memcpy((void *)addr, &value, sizeof(value));
    }
}

MOONBIT_FFI_EXPORT uint32_t wasmoon_jit_read_u32(int64_t addr) {
    uint32_t value = 0;
    if (addr != 0) {
        memcpy(&value, (const void *)addr, sizeof(value));
    }
    return value;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_read_i64(int64_t addr) {
    if (addr != 0) {
        return *((int64_t *)addr);
    }
    return 0;
}

// ============ GC Runtime FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_ref_test_ptr(void) {
    return (int64_t)gc_ref_test_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_ref_cast_ptr(void) {
    return (int64_t)gc_ref_cast_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_new_ptr(void) {
    return (int64_t)gc_struct_new_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_get_ptr(void) {
    return (int64_t)gc_struct_get_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_set_ptr(void) {
    return (int64_t)gc_struct_set_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_ptr(void) {
    return (int64_t)gc_array_new_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_get_ptr(void) {
    return (int64_t)gc_array_get_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_set_ptr(void) {
    return (int64_t)gc_array_set_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_len_ptr(void) {
    return (int64_t)gc_array_len_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_fill_ptr(void) {
    return (int64_t)gc_array_fill_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_copy_ptr(void) {
    return (int64_t)gc_array_copy_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_type_check_subtype_ptr(void) {
    return (int64_t)gc_type_check_subtype_impl;
}

// Inline allocation support (ctx-passing)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_register_struct_inline_ptr(void) {
    return (int64_t)gc_register_struct_inline;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_register_array_inline_ptr(void) {
    return (int64_t)gc_register_array_inline;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_struct_slow_ptr(void) {
    return (int64_t)gc_alloc_struct_slow;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_array_slow_ptr(void) {
    return (int64_t)gc_alloc_array_slow;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_alloc_array_from_values_slow_ptr(void) {
    return (int64_t)gc_alloc_array_from_values_slow;
}

static void wasmoon_jit_gc_push_root_scope_or_trap(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
) {
    if (ctx_gc_push_root_scope_internal(ctx, roots, root_count) == 1) {
        return;
    }
    g_trap_code = 99;
    siglongjmp(g_trap_jmp_buf, 1);
}

static void wasmoon_jit_gc_pop_root_scope_or_trap(jit_context_t *ctx) {
    if (ctx && ctx->gc_root_scope_head) {
        ctx_gc_pop_root_scope_internal(ctx);
        return;
    }
    g_trap_code = 99;
    siglongjmp(g_trap_jmp_buf, 1);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_push_root_scope_ptr(void) {
    return (int64_t)wasmoon_jit_gc_push_root_scope_or_trap;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_pop_root_scope_ptr(void) {
    return (int64_t)wasmoon_jit_gc_pop_root_scope_or_trap;
}

// ============ Type Cache Management FFI Exports ============

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_type_cache(
    int64_t ctx_ptr,
    int32_t *types_data,
    int num_types
) {
    set_type_cache_internal((jit_context_t *)(uintptr_t)ctx_ptr, types_data, num_types);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_canonical_indices(
    int64_t ctx_ptr,
    int32_t *canonical,
    int num_types
) {
    set_canonical_indices_internal((jit_context_t *)(uintptr_t)ctx_ptr, canonical, num_types);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_func_type_indices(
    int64_t ctx_ptr,
    int32_t *indices,
    int num_funcs
) {
    set_func_type_indices_internal((jit_context_t *)(uintptr_t)ctx_ptr, indices, num_funcs);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_func_table(
    int64_t ctx_ptr,
    int64_t func_table_ptr,
    int num_funcs
) {
    set_func_table_internal((jit_context_t *)(uintptr_t)ctx_ptr, (void **)(uintptr_t)func_table_ptr, num_funcs);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_clear_cache(int64_t ctx_ptr) {
    clear_type_cache_internal((jit_context_t *)(uintptr_t)ctx_ptr);
}

// ============ GC Heap Pointer Management ============

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_heap(int64_t ctx_ptr, int64_t heap_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    GcHeap *heap = (GcHeap *)(uintptr_t)heap_ptr;
    ctx_set_gc_heap_internal(ctx, heap);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_clear_heap(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_set_gc_heap_internal(ctx, NULL);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_gc_get_heap(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return (ctx != NULL) ? (int64_t)(uintptr_t)ctx->gc_heap : 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_gc_heap(int64_t ctx_ptr, int64_t heap_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    GcHeap *heap = (GcHeap *)(uintptr_t)heap_ptr;
    ctx_set_gc_heap_internal(ctx, heap);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_begin_frame(int64_t ctx_ptr, int64_t frame_id) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_begin_frame_internal(ctx, (uintptr_t)frame_id);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_end_frame(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_end_frame_internal(ctx);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_push_root_scope(
    int64_t ctx_ptr,
    int64_t *roots,
    int32_t root_count
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return ctx_gc_push_root_scope_internal(ctx, roots, root_count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_pop_root_scope(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_pop_root_scope_internal(ctx);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_collect_for_alloc(
    int64_t ctx_ptr,
    int64_t *roots,
    int32_t root_count
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return gc_collect_for_alloc_internal(ctx, roots, root_count);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_set_root_scratch(
    int64_t ctx_ptr,
    int64_t *roots,
    int32_t root_count
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return ctx_gc_set_root_scratch_internal(ctx, roots, root_count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_safepoint_table(
    int64_t ctx_ptr,
    int64_t table_ptr
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    const wasmoon_gc_safepoint_table_t *table =
        (const wasmoon_gc_safepoint_table_t *)(uintptr_t)table_ptr;
    ctx_gc_set_safepoint_table_internal(ctx, table);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_gc_set_func_safepoints(
    int64_t ctx_ptr,
    int32_t func_idx,
    uint8_t *stackmap_blob,
    int32_t stackmap_blob_size,
    int32_t *code_offsets,
    int32_t safepoint_count
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    return ctx_gc_set_func_safepoints_internal(
        ctx,
        func_idx,
        stackmap_blob,
        stackmap_blob_size,
        code_offsets,
        safepoint_count
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_use_func_safepoints(
    int64_t ctx_ptr,
    int32_t func_idx
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)ctx_ptr;
    ctx_gc_use_func_safepoints_internal(ctx, func_idx);
}
