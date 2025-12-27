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
    ctx->memory_base = NULL;
    ctx->memory_size = 0;
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
    ctx->memories = NULL;         // Array of memory base pointers
    ctx->memory_sizes = NULL;     // Array of memory sizes
    ctx->memory_max_sizes = NULL; // Array of memory max sizes
    ctx->memory_count = 0;

    // Additional fields (not accessed by JIT code directly)
    ctx->owns_indirect_table = 0; // Default: does not own table0_base
    ctx->args = NULL;
    ctx->argc = 0;
    ctx->envp = NULL;
    ctx->envc = 0;

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

    return ctx;
}

// ============ Context Free ============

void free_context_internal(jit_context_t *ctx) {
    if (!ctx) return;

    if (ctx->func_table) free(ctx->func_table);
    if (ctx->tables) free(ctx->tables);
    if (ctx->table_sizes) free(ctx->table_sizes);
    if (ctx->table_max_sizes) free(ctx->table_max_sizes);
    // Only free table0_base if we own it (allocated via alloc_indirect_table)
    // Borrowed tables (from set_table_pointers) are managed by JITTable's GC
    if (ctx->table0_base && ctx->owns_indirect_table) free(ctx->table0_base);
    if (ctx->memory_base) free(ctx->memory_base);
    if (ctx->globals) free(ctx->globals);

    // Free multi-memory arrays (but not the memory data itself - managed by caller)
    if (ctx->memories) free(ctx->memories);
    if (ctx->memory_sizes) free(ctx->memory_sizes);
    if (ctx->memory_max_sizes) free(ctx->memory_max_sizes);

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

    free(ctx);
}

// ============ Context Setters ============

void ctx_set_func_internal(jit_context_t *ctx, int idx, void *func_ptr) {
    if (ctx && idx >= 0 && idx < ctx->func_count) {
        ctx->func_table[idx] = func_ptr;
    }
}

void ctx_set_memory_internal(jit_context_t *ctx, uint8_t *mem_ptr, size_t mem_size) {
    if (ctx) {
        ctx->memory_base = mem_ptr;
        ctx->memory_size = mem_size;
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
