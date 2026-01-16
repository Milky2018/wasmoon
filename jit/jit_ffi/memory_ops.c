// Copyright 2025
// Memory and table runtime operations for JIT
// Implements memory.grow, memory.fill, memory.copy, table.grow

#include "jit_internal.h"

// ============ Guard Page Memory Allocation ============
// Uses mmap to allocate memory with guard pages for bounds check elimination.
// Strategy: allocate max_pages worth of virtual address space, but only make
// the first current_pages accessible. Access beyond memory_size hits guard pages
// (PROT_NONE), triggering SIGSEGV which is caught and converted to a trap.

// WebAssembly memory32 uses 32-bit addresses plus a 32-bit static offset.
// The effective address can be up to:
//   (2^32 - 1) + (2^32 - 1) + (access_size - 1) < 2^33
// Reserve 8GB (+ one WASM page as slack) so any out-of-bounds access reliably
// lands in a PROT_NONE region within the same mapping and traps via SIGSEGV.
#define WASM32_MAX_MEMORY (4ULL * 1024 * 1024 * 1024)
#define WASM32_GUARD_RESERVATION (WASM32_MAX_MEMORY * 2ULL + WASM_PAGE_SIZE)

// Allocate memory with guard pages using mmap
// Returns memory base on success, NULL on failure
static uint8_t *alloc_guarded_memory(wasmoon_memory_t *memory, size_t initial_size, size_t max_size) {
    if (!memory) return NULL;

    // Reserve a large, fixed virtual range for memory32 guard pages regardless of
    // the module's declared maximum. This avoids OOB accesses escaping the mapping
    // (e.g. addr + offset >= max_size) when bounds checks are eliminated.
    (void)max_size;  // reserved for future memory64 support
    size_t reserve_size = (size_t)WASM32_GUARD_RESERVATION;

    // Align to page size
    size_t page_size = (size_t)getpagesize();
    reserve_size = (reserve_size + page_size - 1) & ~(page_size - 1);
    initial_size = (initial_size + page_size - 1) & ~(page_size - 1);

#ifdef _WIN32
    // Windows: use VirtualAlloc with MEM_RESERVE, then MEM_COMMIT for used pages
    void *mapping = VirtualAlloc(NULL, reserve_size, MEM_RESERVE, PAGE_NOACCESS);
    if (mapping == NULL) return NULL;

    // Commit the initial pages
    if (initial_size > 0) {
        void *committed = VirtualAlloc(mapping, initial_size, MEM_COMMIT, PAGE_READWRITE);
        if (committed == NULL) {
            VirtualFree(mapping, 0, MEM_RELEASE);
            return NULL;
        }
    }
#else
    // POSIX: use mmap with PROT_NONE, then mprotect for used pages
    void *mapping = mmap(NULL, reserve_size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return NULL;

    // Make the initial pages accessible
    if (initial_size > 0) {
        if (mprotect(mapping, initial_size, PROT_READ | PROT_WRITE) != 0) {
            munmap(mapping, reserve_size);
            return NULL;
        }
        // Zero-initialize (mmap with MAP_ANONYMOUS should already be zero, but be safe)
        memset(mapping, 0, initial_size);
    }
#endif

    // Store allocation info in memory object
    memory->alloc_base = mapping;
    memory->alloc_size = reserve_size;
    memory->guard_start = initial_size;
    memory->is_guarded = 1;
    memory->base = (uint8_t *)mapping;
    atomic_store_explicit(&memory->current_length, initial_size, memory_order_relaxed);

    return (uint8_t *)mapping;
}

// Grow guarded memory by changing protection
static int grow_guarded_memory(wasmoon_memory_t *memory, size_t old_size, size_t new_size) {
    if (!memory || !memory->alloc_base) return -1;
    if (new_size > memory->alloc_size) return -1;  // Would exceed reservation

    size_t page_size = (size_t)getpagesize();
    old_size = (old_size + page_size - 1) & ~(page_size - 1);
    new_size = (new_size + page_size - 1) & ~(page_size - 1);

    if (new_size <= old_size) return 0;  // Nothing to do

    uint8_t *base = (uint8_t *)memory->alloc_base;
    size_t grow_size = new_size - old_size;

#ifdef _WIN32
    // Windows: commit new pages
    void *committed = VirtualAlloc(base + old_size, grow_size, MEM_COMMIT, PAGE_READWRITE);
    if (committed == NULL) return -1;
#else
    // POSIX: mprotect new pages
    if (mprotect(base + old_size, grow_size, PROT_READ | PROT_WRITE) != 0) {
        return -1;
    }
#endif

    // Zero-initialize new pages
    memset(base + old_size, 0, grow_size);
    memory->guard_start = new_size;
    atomic_store_explicit(&memory->current_length, new_size, memory_order_relaxed);

    return 0;
}

// Free guarded memory
static void free_guarded_memory(wasmoon_memory_t *memory) {
    if (!memory || !memory->alloc_base || !memory->is_guarded) return;

#ifdef _WIN32
    VirtualFree(memory->alloc_base, 0, MEM_RELEASE);
#else
    munmap(memory->alloc_base, memory->alloc_size);
#endif

    memory->alloc_base = NULL;
    memory->alloc_size = 0;
    memory->guard_start = 0;
    memory->base = NULL;
    atomic_store_explicit(&memory->current_length, 0, memory_order_relaxed);
    memory->is_guarded = 0;
}

// External version of alloc_guarded_memory (used by jit.c)
uint8_t *alloc_guarded_memory_external(wasmoon_memory_t *memory, size_t initial_size, size_t max_size) {
    return alloc_guarded_memory(memory, initial_size, max_size);
}

// Check if address is in the guard region of memory0
int is_memory_guard_page_access(jit_context_t *ctx, void *addr) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->is_guarded || !ctx->memory0->alloc_base) return 0;

    uintptr_t alloc_base = (uintptr_t)ctx->memory0->alloc_base;
    uintptr_t alloc_end = alloc_base + ctx->memory0->alloc_size;
    uintptr_t guard_start = alloc_base + ctx->memory0->guard_start;
    uintptr_t fault_addr = (uintptr_t)addr;

    // Check if fault is in the guard region (after accessible memory, within allocation)
    return (fault_addr >= guard_start && fault_addr < alloc_end);
}

// ============ Linear Memory Operations ============

int32_t memory_grow_ctx_internal(jit_context_t *ctx, int32_t delta, int32_t max_pages) {
    if (!ctx || !ctx->memory0) return -1;
    if (delta < 0) return -1;

    wasmoon_memory_t *mem = ctx->memory0;
    size_t page_size = (size_t)1 << (size_t)mem->page_size_log2;
    if (page_size == 0) return -1;

    size_t current_size = atomic_load_explicit(&mem->current_length, memory_order_relaxed);
    int64_t current_pages = (int64_t)(current_size / page_size);

    int64_t new_pages = current_pages + (int64_t)delta;

    // Spec max: memory32 has a 32-bit address space (4GiB bytes).
    int64_t arch_max_pages;
    if (mem->is_memory64) {
        arch_max_pages = 2147483647LL;
    } else {
        const int64_t max_bytes = 4294967296LL;
        arch_max_pages = (page_size == 0) ? 0 : (max_bytes / (int64_t)page_size);
    }
    if (new_pages > arch_max_pages) return -1;

    // Check against configured max limit.
    // max_pages < 0 means "use descriptor's max".
    uint64_t stored_max = (uint64_t)mem->max_pages;
    uint64_t effective_max = (max_pages >= 0) ? (uint64_t)max_pages : stored_max;

    // SIZE_MAX in the descriptor means "unlimited".
    if (effective_max == (uint64_t)SIZE_MAX) {
        effective_max = (uint64_t)arch_max_pages;
    }

    if ((uint64_t)new_pages > effective_max) return -1;

    // No change needed if delta is 0
    if (delta == 0) return (int32_t)current_pages;

    size_t new_size = (size_t)new_pages * page_size;

    if (mem->is_guarded) {
        if (grow_guarded_memory(mem, current_size, new_size) != 0) {
            return -1;
        }
        return (int32_t)current_pages;
    }

    uint8_t *new_base = (uint8_t *)realloc(mem->base, new_size);
    if (!new_base) return -1;

    memset(new_base + current_size, 0, new_size - current_size);

    mem->base = new_base;
    atomic_store_explicit(&mem->current_length, new_size, memory_order_relaxed);

    return (int32_t)current_pages;
}

int32_t memory_size_ctx_internal(jit_context_t *ctx) {
    if (!ctx || !ctx->memory0) return 0;
    wasmoon_memory_t *mem = ctx->memory0;
    size_t page_size = (size_t)1 << (size_t)mem->page_size_log2;
    if (page_size == 0) return 0;
    size_t size = atomic_load_explicit(&mem->current_length, memory_order_relaxed);
    return (int32_t)(size / page_size);
}

// ============ Descriptor-Only Operations (no ctx) ============

int64_t memory_len_desc_internal(wasmoon_memory_t *mem) {
    if (!mem) return 0;
    return (int64_t)atomic_load_explicit(&mem->current_length, memory_order_relaxed);
}

uint8_t *memory_base_desc_internal(wasmoon_memory_t *mem) {
    return mem ? mem->base : NULL;
}

int32_t memory_grow_desc_internal(wasmoon_memory_t *mem, int32_t delta, int32_t max_pages) {
    if (!mem) return -1;
    if (delta < 0) return -1;

    size_t page_size = (size_t)1 << (size_t)mem->page_size_log2;
    if (page_size == 0) return -1;

    size_t current_size = atomic_load_explicit(&mem->current_length, memory_order_relaxed);
    int64_t current_pages = (int64_t)(current_size / page_size);

    int64_t new_pages = current_pages + (int64_t)delta;

    int64_t arch_max_pages;
    if (mem->is_memory64) {
        arch_max_pages = 2147483647LL;
    } else {
        const int64_t max_bytes = 4294967296LL;
        arch_max_pages = max_bytes / (int64_t)page_size;
    }
    if (new_pages > arch_max_pages) return -1;

    uint64_t stored_max = (uint64_t)mem->max_pages;
    uint64_t effective_max = (max_pages >= 0) ? (uint64_t)max_pages : stored_max;

    if (effective_max == (uint64_t)SIZE_MAX) {
        effective_max = (uint64_t)arch_max_pages;
    }

    if ((uint64_t)new_pages > effective_max) return -1;

    if (delta == 0) return (int32_t)current_pages;

    size_t new_size = (size_t)new_pages * page_size;

    if (mem->is_guarded) {
        if (grow_guarded_memory(mem, current_size, new_size) != 0) {
            return -1;
        }
        return (int32_t)current_pages;
    }

    uint8_t *new_base = (uint8_t *)realloc(mem->base, new_size);
    if (!new_base) return -1;

    memset(new_base + current_size, 0, new_size - current_size);

    mem->base = new_base;
    atomic_store_explicit(&mem->current_length, new_size, memory_order_relaxed);

    return (int32_t)current_pages;
}

// ============ Multi-Memory Operations (v4 with memidx) ============

// Helper to get memory object for a given memidx
static wasmoon_memory_t *get_memory(jit_context_t *ctx, int32_t memidx) {
    if (!ctx || memidx < 0) return NULL;
    if (memidx == 0) return ctx->memory0;
    if (!ctx->memories || memidx >= ctx->memory_count) return NULL;
    return ctx->memories[memidx];
}

static uint8_t *get_memory_base(jit_context_t *ctx, int32_t memidx) {
    wasmoon_memory_t *mem = get_memory(ctx, memidx);
    return mem ? mem->base : NULL;
}

static size_t get_memory_size(jit_context_t *ctx, int32_t memidx) {
    wasmoon_memory_t *mem = get_memory(ctx, memidx);
    return mem ? atomic_load_explicit(&mem->current_length, memory_order_relaxed) : 0;
}

static size_t get_memory_max_pages(jit_context_t *ctx, int32_t memidx) {
    wasmoon_memory_t *mem = get_memory(ctx, memidx);
    if (!mem) {
        return 65536;
    }

    // SIZE_MAX means "unlimited".
    if (mem->max_pages == SIZE_MAX) {
        if (mem->is_memory64) {
            return (size_t)2147483647;
        }
        size_t page_size = (size_t)1 << (size_t)mem->page_size_log2;
        if (page_size == 0) {
            return 65536;
        }
        return (size_t)(4294967296ULL / (uint64_t)page_size);
    }

    // Otherwise, the declared maximum can legally be 0.
    return mem->max_pages;
}

static void set_memory(jit_context_t *ctx, int32_t memidx, uint8_t *base, size_t size) {
    wasmoon_memory_t *mem = get_memory(ctx, memidx);
    if (!mem) return;
    mem->base = base;
    atomic_store_explicit(&mem->current_length, size, memory_order_relaxed);
    if (mem->is_guarded) {
        mem->guard_start = size;
    }
}

int32_t memory_grow_indexed_internal(jit_context_t *ctx, int32_t memidx, int32_t delta, int32_t max_pages) {
    if (!ctx) return -1;
    if (delta < 0) return -1;
    if (memidx < 0) return -1;
    if (memidx > 0 && (!ctx->memories || memidx >= ctx->memory_count)) return -1;

    wasmoon_memory_t *mem = get_memory(ctx, memidx);
    if (!mem) return -1;

    size_t page_size = (size_t)1 << (size_t)mem->page_size_log2;
    if (page_size == 0) return -1;

    uint8_t *mem_base = mem->base;
    size_t current_size = atomic_load_explicit(&mem->current_length, memory_order_relaxed);
    int64_t current_pages = (int64_t)(current_size / page_size);

    int64_t new_pages = current_pages + (int64_t)delta;

    // Check against max limit (pages)
    int64_t stored_max = (int64_t)get_memory_max_pages(ctx, memidx);
    int64_t effective_max = (max_pages >= 0) ? (int64_t)max_pages : stored_max;
    if (effective_max > stored_max) effective_max = stored_max;
    if (new_pages > effective_max) return -1;

    // No change needed if delta is 0
    if (delta == 0) return (int32_t)current_pages;

    size_t new_size = (size_t)new_pages * page_size;

    if (mem->is_guarded) {
        if (grow_guarded_memory(mem, current_size, new_size) != 0) {
            return -1;
        }
        return (int32_t)current_pages;
    }

    uint8_t *new_mem = (uint8_t *)realloc(mem_base, new_size);
    if (!new_mem) return -1;

    memset(new_mem + current_size, 0, new_size - current_size);

    set_memory(ctx, memidx, new_mem, new_size);

    return (int32_t)current_pages;
}

int32_t memory_size_indexed_internal(jit_context_t *ctx, int32_t memidx) {
    if (!ctx) return 0;
    if (memidx < 0) return 0;
    if (memidx > 0 && (!ctx->memories || memidx >= ctx->memory_count)) return 0;

    wasmoon_memory_t *mem = get_memory(ctx, memidx);
    if (!mem) return 0;
    size_t page_size = (size_t)1 << (size_t)mem->page_size_log2;
    if (page_size == 0) return 0;

    size_t size = atomic_load_explicit(&mem->current_length, memory_order_relaxed);
    return (int32_t)(size / page_size);
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
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    size_t mem_size = atomic_load_explicit(&ctx->memory0->current_length, memory_order_relaxed);

    // Check bounds
    if (dst < 0 || size < 0 || (uint32_t)dst + (uint32_t)size > mem_size) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Fill memory with byte value (val & 0xFF)
    memset(ctx->memory0->base + dst, val & 0xFF, size);
}

void memory_copy_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t src, int32_t size) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    size_t mem_size = atomic_load_explicit(&ctx->memory0->current_length, memory_order_relaxed);

    // Check bounds for both source and destination
    if (dst < 0 || src < 0 || size < 0 ||
        (uint32_t)dst + (uint32_t)size > mem_size ||
        (uint32_t)src + (uint32_t)size > mem_size) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Use memmove to handle overlapping regions correctly
    memmove(ctx->memory0->base + dst, ctx->memory0->base + src, size);
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
