// Copyright 2025
// JIT context management
// Handles allocation, configuration, and lifecycle of jit_context_t

#include "jit_internal.h"

// ============ Context Allocation ============

jit_context_t *alloc_context_internal(int func_count) {
    jit_context_t *ctx = (jit_context_t *)malloc(sizeof(jit_context_t));
    if (!ctx) return NULL;

    // Initialize all fields to match VMContext v3 layout
    // High frequency fields
    ctx->memory0 = NULL;
    ctx->func_table = (void **)calloc(func_count, sizeof(void *));
    if (!ctx->func_table) {
        free(ctx);
        return NULL;
    }
    ctx->table0_base = NULL;      // Table 0 base (fast path for call_indirect)

    // Medium frequency fields
    ctx->table0_elements = 0;     // Table 0 element count
    ctx->globals = NULL;

    // Low frequency fields (multi-table support)
    ctx->tables = NULL;           // Array of table pointers (for table_idx != 0)
    ctx->table_count = 0;
    ctx->func_count = func_count;
    ctx->table_sizes = NULL;      // Array of table sizes
    ctx->table_max_sizes = NULL;  // Array of table max sizes

    // Multi-memory support
    ctx->memories = NULL;         // Array of memory definition pointers
    ctx->memory_count = 0;
    ctx->debug_current_func_idx = -1;

    // GC heap for inline allocation
    ctx->gc_heap_ptr = NULL;      // Current allocation pointer
    ctx->gc_heap_limit = NULL;    // Allocation limit
    ctx->gc_heap = NULL;          // GcHeap* pointer

    // Additional fields (not accessed by JIT code directly)
    ctx->owns_memory0 = 0;        // Default: does not own memory0
    ctx->owns_indirect_table = 0; // Default: does not own table0_base
    ctx->args = NULL;
    ctx->argc = 0;
    ctx->envp = NULL;
    ctx->envc = 0;
    ctx->wasi_exited = 0;
    ctx->wasi_exit_code = 0;

    // Exception handling state
    ctx->exception_handler = NULL;
    ctx->exception_tag = 0;
    ctx->exception_values = NULL;
    ctx->exception_value_count = 0;

    // Spilled locals for exception handling
    ctx->spilled_locals = NULL;
    ctx->spilled_locals_count = 0;

    // WASM stack (initially not allocated)
    ctx->wasm_stack_base = NULL;
    ctx->wasm_stack_top = NULL;
    ctx->wasm_stack_size = 0;
    ctx->wasm_stack_guard = NULL;
    ctx->guard_page_size = 0;

    // WASI fd/preopen state (init_wasi_* may not be called for some contexts)
    ctx->fd_table = NULL;
    ctx->fd_table_size = 0;
    ctx->fd_next = 0;
    ctx->fd_host_paths = NULL;
    ctx->fd_is_dir = NULL;
    ctx->preopen_paths = NULL;
    ctx->preopen_guest_paths = NULL;
    ctx->preopen_count = 0;
    ctx->preopen_base_fd = 0;

    // WASI stdio buffers (disabled by default)
    ctx->wasi_stdin_use_buffer = 0;
    ctx->wasi_stdin_buf = NULL;
    ctx->wasi_stdin_len = 0;
    ctx->wasi_stdin_offset = 0;
    ctx->wasi_stdin_callback = NULL;
    ctx->wasi_stdin_callback_data = NULL;
    ctx->wasi_stdout_capture = 0;
    ctx->wasi_stdout_buf = NULL;
    ctx->wasi_stdout_len = 0;
    ctx->wasi_stdout_cap = 0;
    ctx->wasi_stderr_capture = 0;
    ctx->wasi_stderr_buf = NULL;
    ctx->wasi_stderr_len = 0;
    ctx->wasi_stderr_cap = 0;

    return ctx;
}

// ============ Context Free ============


void free_context_internal(jit_context_t *ctx) {
    if (!ctx) return;

    // Free context-owned memory0 (guarded allocations are large and must not leak)
    if (ctx->owns_memory0 && ctx->memory0) {
        wasmoon_jit_free_memory_desc((int64_t)ctx->memory0);
        ctx->memory0 = NULL;
        ctx->owns_memory0 = 0;
    }

    if (ctx->func_table) free(ctx->func_table);
    if (ctx->tables) free(ctx->tables);
    if (ctx->table_sizes) free(ctx->table_sizes);
    if (ctx->table_max_sizes) free(ctx->table_max_sizes);
    // Only free table0_base if we own it (allocated via alloc_indirect_table)
    // Borrowed tables (from set_table_pointers) are managed by JITTable's GC
    if (ctx->table0_base && ctx->owns_indirect_table) free(ctx->table0_base);
    // Do not free memories here: memories are owned by the runtime Store and
    // can be shared across multiple instances/contexts.
    if (ctx->globals) free(ctx->globals);

    // Free multi-memory arrays (but not the memory data itself - managed by runtime)
    if (ctx->memories) free(ctx->memories);

    // Free exception handling state
    if (ctx->exception_values) free(ctx->exception_values);
    // Free any remaining exception handlers
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;
    while (handler) {
        exception_handler_t *prev = handler->prev;
        free(handler);
        handler = prev;
    }
    // Free spilled locals
    if (ctx->spilled_locals) free(ctx->spilled_locals);

    // Free WASM stack (if allocated)
    if (ctx->wasm_stack_base) {
        munmap(ctx->wasm_stack_base, ctx->wasm_stack_size);
    }

    // Free WASI resources (fds, args/env, stdio buffers)
    wasmoon_jit_free_wasi_fds((int64_t)ctx);

    free(ctx);
}

// ============ Context Setters ============

void ctx_set_func_internal(jit_context_t *ctx, int idx, void *func_ptr) {
    if (ctx && idx >= 0 && idx < ctx->func_count) {
        ctx->func_table[idx] = func_ptr;
    }
}

void ctx_set_memory_internal(jit_context_t *ctx, wasmoon_memory_t *mem0) {
    if (ctx) {
        ctx->memory0 = mem0;
    }
}

void ctx_set_globals_internal(jit_context_t *ctx, void *globals_ptr) {
    if (ctx) {
        ctx->globals = globals_ptr;
    }
}

// ============ Indirect Table Management ============

int ctx_alloc_indirect_table_internal(jit_context_t *ctx, int count) {
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
    ctx->owns_indirect_table = 1;  // We own this table
    return 1;
}

void ctx_set_indirect_internal(jit_context_t *ctx, int table_idx, int func_idx, int type_idx) {
    if (ctx && ctx->table0_base &&
        table_idx >= 0 && (size_t)table_idx < ctx->table0_elements &&
        func_idx >= 0 && func_idx < ctx->func_count) {
        // Store func_ptr at offset 0, type_idx at offset 8
        ctx->table0_base[table_idx * 2] = ctx->func_table[func_idx];
        ctx->table0_base[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
    }
}

void ctx_use_shared_table_internal(jit_context_t *ctx, void **shared_table, int count) {
    if (!ctx) return;

    // Free existing table0_base only if we own it
    if (ctx->table0_base && ctx->owns_indirect_table) {
        free(ctx->table0_base);
    }

    // Point to the shared table (borrowed, not owned)
    ctx->table0_base = shared_table;
    ctx->table0_elements = count;
    ctx->owns_indirect_table = 0;  // We don't own this table
}

// ============ Multi-Table Support ============

void ctx_set_table_pointers_internal(
    jit_context_t *ctx,
    int64_t *table_ptrs,
    int32_t *table_sizes,
    int32_t *table_max_sizes,
    int table_count
) {
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

    // Allocate array to hold table pointers
    ctx->tables = (void ***)calloc(table_count, sizeof(void **));
    if (!ctx->tables) return;

    // Allocate array to hold table sizes
    ctx->table_sizes = (size_t *)calloc(table_count, sizeof(size_t));
    if (!ctx->table_sizes) {
        free(ctx->tables);
        ctx->tables = NULL;
        return;
    }

    // Allocate array to hold table max sizes
    ctx->table_max_sizes = (size_t *)calloc(table_count, sizeof(size_t));
    if (!ctx->table_max_sizes) {
        free(ctx->tables);
        free(ctx->table_sizes);
        ctx->tables = NULL;
        ctx->table_sizes = NULL;
        return;
    }

    // Copy table pointers, sizes, and max sizes
    for (int i = 0; i < table_count; i++) {
        ctx->tables[i] = (void **)table_ptrs[i];
        if (table_sizes) {
            ctx->table_sizes[i] = (size_t)table_sizes[i];
        }
        if (table_max_sizes) {
            // -1 means unlimited, store as SIZE_MAX
            ctx->table_max_sizes[i] = (table_max_sizes[i] < 0) ? SIZE_MAX : (size_t)table_max_sizes[i];
        } else {
            ctx->table_max_sizes[i] = SIZE_MAX;  // Default: unlimited
        }
    }
    ctx->table_count = table_count;

    // For backward compatibility: if there's at least one table, set it as table0_base
    if (table_count > 0 && table_ptrs[0] != 0) {
        ctx->table0_base = (void **)table_ptrs[0];
        ctx->owns_indirect_table = 0;  // Borrowed from JITTable, not owned
        if (table_sizes) {
            ctx->table0_elements = table_sizes[0];
        }
    }
}

// ============ GC Heap Support ============

void ctx_set_gc_heap_internal(jit_context_t *ctx, GcHeap *heap) {
    if (!ctx) return;

    ctx->gc_heap = heap;
    if (heap) {
        // Set up pointers for inline allocation
        ctx->gc_heap_ptr = heap->data + heap->size;
        ctx->gc_heap_limit = heap->data + heap->capacity;
    } else {
        ctx->gc_heap_ptr = NULL;
        ctx->gc_heap_limit = NULL;
    }
}

void ctx_update_gc_heap_ptr_internal(jit_context_t *ctx) {
    if (!ctx || !ctx->gc_heap) return;

    GcHeap *heap = (GcHeap *)ctx->gc_heap;
    ctx->gc_heap_ptr = heap->data + heap->size;
    ctx->gc_heap_limit = heap->data + heap->capacity;
}
