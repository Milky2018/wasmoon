// Copyright 2025
// Memory and table runtime operations for JIT
// Implements memory.grow, memory.fill, memory.copy, table.grow

#include "jit_internal.h"

// ============ Linear Memory Operations ============

int32_t memory_grow_ctx_internal(jit_context_t *ctx, int32_t delta, int32_t max_pages) {
    if (!ctx) return -1;
    if (delta < 0) return -1;

    size_t current_size = ctx->memory_size;
    int32_t current_pages = (int32_t)(current_size / WASM_PAGE_SIZE);

    // Check for overflow
    int64_t new_pages_64 = (int64_t)current_pages + (int64_t)delta;
    if (new_pages_64 > 65536) return -1;  // Max 4GB (65536 pages)

    // Check against max limit
    int32_t effective_max = (max_pages > 0) ? max_pages : 65536;
    if (new_pages_64 > effective_max) return -1;

    int32_t new_pages = (int32_t)new_pages_64;
    size_t new_size = (size_t)new_pages * WASM_PAGE_SIZE;

    // No change needed if delta is 0
    if (delta == 0) return current_pages;

    // Reallocate memory
    uint8_t *new_mem = (uint8_t *)realloc(ctx->memory_base, new_size);
    if (!new_mem) return -1;

    // Zero-initialize the new pages
    memset(new_mem + current_size, 0, new_size - current_size);

    // Update context
    ctx->memory_base = new_mem;
    ctx->memory_size = new_size;

    return current_pages;
}

int32_t memory_size_ctx_internal(jit_context_t *ctx) {
    if (!ctx) return 0;
    return (int32_t)(ctx->memory_size / WASM_PAGE_SIZE);
}

// ============ Multi-Memory Operations (v4 with memidx) ============

// Helper to get memory base for a given memidx
static uint8_t *get_memory_base(jit_context_t *ctx, int32_t memidx) {
    if (memidx == 0) {
        return ctx->memory_base;
    }
    if (!ctx->memories || memidx < 0 || memidx >= ctx->memory_count) {
        return NULL;
    }
    return ctx->memories[memidx];
}

// Helper to get memory size for a given memidx
static size_t get_memory_size(jit_context_t *ctx, int32_t memidx) {
    if (memidx == 0) {
        return ctx->memory_size;
    }
    if (!ctx->memory_sizes || memidx < 0 || memidx >= ctx->memory_count) {
        return 0;
    }
    return ctx->memory_sizes[memidx];
}

// Helper to get memory max pages for a given memidx
static size_t get_memory_max_pages(jit_context_t *ctx, int32_t memidx) {
    if (!ctx->memory_max_sizes || memidx < 0 || memidx >= ctx->memory_count) {
        return 65536;  // Default max of 4GB (65536 pages)
    }
    return ctx->memory_max_sizes[memidx];
}

// Helper to set memory base and size for a given memidx
static void set_memory(jit_context_t *ctx, int32_t memidx, uint8_t *base, size_t size) {
    if (memidx == 0) {
        ctx->memory_base = base;
        ctx->memory_size = size;
    }
    if (ctx->memories && memidx >= 0 && memidx < ctx->memory_count) {
        ctx->memories[memidx] = base;
        if (ctx->memory_sizes) {
            ctx->memory_sizes[memidx] = size;
        }
    }
}

int32_t memory_grow_indexed_internal(jit_context_t *ctx, int32_t memidx, int32_t delta, int32_t max_pages) {
    if (!ctx) return -1;
    if (delta < 0) return -1;
    if (memidx < 0) return -1;
    if (memidx > 0 && (!ctx->memories || memidx >= ctx->memory_count)) return -1;

    uint8_t *mem_base = get_memory_base(ctx, memidx);
    size_t current_size = get_memory_size(ctx, memidx);
    int32_t current_pages = (int32_t)(current_size / WASM_PAGE_SIZE);

    // Check for overflow
    int64_t new_pages_64 = (int64_t)current_pages + (int64_t)delta;
    if (new_pages_64 > 65536) return -1;  // Max 4GB (65536 pages)

    // Check against max limit
    int32_t effective_max;
    if (max_pages > 0) {
        effective_max = max_pages;
    } else {
        size_t stored_max = get_memory_max_pages(ctx, memidx);
        effective_max = (stored_max > 65536) ? 65536 : (int32_t)stored_max;
    }
    if (new_pages_64 > effective_max) return -1;

    int32_t new_pages = (int32_t)new_pages_64;
    size_t new_size = (size_t)new_pages * WASM_PAGE_SIZE;

    // No change needed if delta is 0
    if (delta == 0) return current_pages;

    // Reallocate memory
    uint8_t *new_mem = (uint8_t *)realloc(mem_base, new_size);
    if (!new_mem) return -1;

    // Zero-initialize the new pages
    memset(new_mem + current_size, 0, new_size - current_size);

    // Update context
    set_memory(ctx, memidx, new_mem, new_size);

    return current_pages;
}

int32_t memory_size_indexed_internal(jit_context_t *ctx, int32_t memidx) {
    if (!ctx) return 0;
    if (memidx < 0) return 0;
    if (memidx > 0 && (!ctx->memories || memidx >= ctx->memory_count)) return 0;

    size_t size = get_memory_size(ctx, memidx);
    return (int32_t)(size / WASM_PAGE_SIZE);
}

void memory_fill_indexed_internal(jit_context_t *ctx, int32_t memidx, int32_t dst, int32_t val, int32_t size) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    if (memidx < 0 || (memidx > 0 && (!ctx->memories || memidx >= ctx->memory_count))) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    uint8_t *mem_base = get_memory_base(ctx, memidx);
    size_t mem_size = get_memory_size(ctx, memidx);

    if (!mem_base) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Check bounds
    if (dst < 0 || size < 0 || (uint32_t)dst + (uint32_t)size > mem_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Fill memory with byte value (val & 0xFF)
    memset(mem_base + dst, val & 0xFF, size);
}

void memory_copy_indexed_internal(jit_context_t *ctx, int32_t dst_memidx, int32_t src_memidx,
                                   int32_t dst, int32_t src, int32_t size) {
    if (!ctx) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    if (dst_memidx < 0 || src_memidx < 0) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    if ((dst_memidx > 0 && (!ctx->memories || dst_memidx >= ctx->memory_count)) ||
        (src_memidx > 0 && (!ctx->memories || src_memidx >= ctx->memory_count))) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    uint8_t *dst_base = get_memory_base(ctx, dst_memidx);
    size_t dst_size = get_memory_size(ctx, dst_memidx);
    uint8_t *src_base = get_memory_base(ctx, src_memidx);
    size_t src_size = get_memory_size(ctx, src_memidx);

    if (!dst_base || !src_base) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Check bounds for both source and destination
    if (dst < 0 || src < 0 || size < 0 ||
        (uint32_t)dst + (uint32_t)size > dst_size ||
        (uint32_t)src + (uint32_t)size > src_size) {
        g_trap_code = 1;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }

    // Use memmove if same memory (handles overlapping regions), memcpy otherwise
    if (dst_memidx == src_memidx) {
        memmove(dst_base + dst, src_base + src, size);
    } else {
        memcpy(dst_base + dst, src_base + src, size);
    }
}

// ============ Bulk Memory Operations ============

void memory_fill_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t val, int32_t size) {
    if (!ctx || !ctx->memory_base) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Check bounds
    if (dst < 0 || size < 0 || (uint32_t)dst + (uint32_t)size > ctx->memory_size) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Fill memory with byte value (val & 0xFF)
    memset(ctx->memory_base + dst, val & 0xFF, size);
}

void memory_copy_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t src, int32_t size) {
    if (!ctx || !ctx->memory_base) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Check bounds for both source and destination
    if (dst < 0 || src < 0 || size < 0 ||
        (uint32_t)dst + (uint32_t)size > ctx->memory_size ||
        (uint32_t)src + (uint32_t)size > ctx->memory_size) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Use memmove to handle overlapping regions correctly
    memmove(ctx->memory_base + dst, ctx->memory_base + src, size);
}

// ============ Table Operations ============

int32_t table_grow_ctx_internal(
    jit_context_t *ctx,
    int32_t table_idx,
    int64_t delta,
    int64_t init_value
) {
    if (!ctx || table_idx < 0 || delta < 0) return -1;
    if (table_idx >= ctx->table_count) return -1;
    if (!ctx->tables || !ctx->table_sizes) return -1;

    size_t old_size = ctx->table_sizes[table_idx];
    size_t new_size = old_size + (size_t)delta;

    // Check for overflow
    if (new_size < old_size) return -1;

    // Check against max size limit
    if (ctx->table_max_sizes) {
        size_t max_size = ctx->table_max_sizes[table_idx];
        if (new_size > max_size) return -1;
    }

    // Get the old table pointer
    void **old_table = ctx->tables[table_idx];

    // Allocate new table (2 slots per entry: func_ptr and type_idx)
    void **new_table = (void **)calloc(new_size * 2, sizeof(void *));
    if (!new_table) return -1;

    // Copy existing elements
    if (old_table && old_size > 0) {
        memcpy(new_table, old_table, old_size * 2 * sizeof(void *));
    }

    // Initialize new elements with init_value
    for (size_t i = old_size; i < new_size; i++) {
        new_table[i * 2] = (void *)init_value;      // func_ptr
        new_table[i * 2 + 1] = (void*)(intptr_t)(-1); // type_idx (unknown)
    }

    // Update the tables array
    ctx->tables[table_idx] = new_table;
    ctx->table_sizes[table_idx] = new_size;

    // Update table0 fast path if this is table 0
    if (table_idx == 0) {
        ctx->table0_base = new_table;
        ctx->table0_elements = new_size;
    }

    // Free old table
    if (old_table) {
        free(old_table);
    }

    return (int32_t)old_size;
}
