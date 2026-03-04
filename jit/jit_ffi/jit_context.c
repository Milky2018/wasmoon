// Copyright 2025
// JIT context management
// Handles allocation, configuration, and lifecycle of jit_context_t

#include "jit_internal.h"

static int gc_collect_debug_cached = -1;

static int gc_collect_is_truthy_env(const char *value) {
    if (!value) return 0;
    return strcmp(value, "1") == 0 ||
           strcmp(value, "true") == 0 ||
           strcmp(value, "TRUE") == 0 ||
           strcmp(value, "yes") == 0 ||
           strcmp(value, "YES") == 0 ||
           strcmp(value, "on") == 0 ||
           strcmp(value, "ON") == 0;
}

static int gc_collect_debug_enabled(void) {
    if (gc_collect_debug_cached < 0) {
        gc_collect_debug_cached =
            gc_collect_is_truthy_env(getenv("WASMOON_GC_ALLOC_DEBUG")) ? 1 : 0;
    }
    return gc_collect_debug_cached;
}

// ============ Context Allocation ============

jit_context_t *alloc_context_internal(int func_count) {
    jit_context_t *ctx = (jit_context_t *)malloc(sizeof(jit_context_t));
    if (!ctx) return NULL;

    // Initialize all fields to match VMContext v3 layout
    // High frequency fields
    ctx->memory0 = NULL;
    ctx->memory0_base = NULL;
    atomic_store_explicit(&ctx->memory0_size, 0, memory_order_relaxed);
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
    ctx->gc_type_cache = NULL;
    ctx->gc_num_types = 0;
    ctx->gc_canonical_indices = NULL;
    ctx->gc_num_canonical = 0;
    ctx->gc_func_type_indices = NULL;
    ctx->gc_num_funcs = 0;
    ctx->gc_func_table = NULL;
    ctx->gc_func_table_size = 0;
    ctx->gc_collect_requested = 0;
    ctx->gc_in_collect = 0;
    ctx->gc_root_scratch = NULL;
    ctx->gc_root_scratch_len = 0;
    ctx->gc_root_scratch_cap = 0;
    ctx->gc_safepoint_table = NULL;
    ctx->gc_frame_chain_head = NULL;

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
    ctx->hostcall_callback = NULL;
    ctx->hostcall_callback_data = NULL;
    ctx->wasi_stdout_capture = 0;
    ctx->wasi_stdout_buf = NULL;
    ctx->wasi_stdout_len = 0;
    ctx->wasi_stdout_cap = 0;
    ctx->wasi_stderr_capture = 0;
    ctx->wasi_stderr_buf = NULL;
    ctx->wasi_stderr_len = 0;
    ctx->wasi_stderr_cap = 0;

    // Bulk segment state (per-context; initialized on demand).
    ctx->data_segments = NULL;
    ctx->data_segment_sizes = NULL;
    ctx->data_dropped = NULL;
    ctx->data_segment_count = 0;

    ctx->elem_segments = NULL;
    ctx->elem_segment_sizes = NULL;
    ctx->elem_dropped = NULL;
    ctx->elem_segment_count = 0;

    return ctx;
}

// ============ Context Free ============


void free_context_internal(jit_context_t *ctx) {
    if (!ctx) return;

    // Free per-context segment storage (malloc-owned copies).
    if (ctx->data_segments) {
        for (int i = 0; i < ctx->data_segment_count; i++) {
            if (ctx->data_segments[i]) {
                free(ctx->data_segments[i]);
            }
        }
        free(ctx->data_segments);
        ctx->data_segments = NULL;
    }
    if (ctx->data_segment_sizes) {
        free(ctx->data_segment_sizes);
        ctx->data_segment_sizes = NULL;
    }
    if (ctx->data_dropped) {
        free(ctx->data_dropped);
        ctx->data_dropped = NULL;
    }
    ctx->data_segment_count = 0;

    if (ctx->elem_segments) {
        for (int i = 0; i < ctx->elem_segment_count; i++) {
            if (ctx->elem_segments[i]) {
                free(ctx->elem_segments[i]);
            }
        }
        free(ctx->elem_segments);
        ctx->elem_segments = NULL;
    }
    if (ctx->elem_segment_sizes) {
        free(ctx->elem_segment_sizes);
        ctx->elem_segment_sizes = NULL;
    }
    if (ctx->elem_dropped) {
        free(ctx->elem_dropped);
        ctx->elem_dropped = NULL;
    }
    ctx->elem_segment_count = 0;

    // Free context-owned memory0 (guarded allocations are large and must not leak)
    if (ctx->owns_memory0 && ctx->memory0) {
        wasmoon_jit_free_memory_desc((int64_t)ctx->memory0);
        ctx->memory0 = NULL;
        ctx->memory0_base = NULL;
        atomic_store_explicit(&ctx->memory0_size, 0, memory_order_relaxed);
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

    if (ctx->gc_type_cache) {
        free(ctx->gc_type_cache);
    }
    if (ctx->gc_canonical_indices) {
        free(ctx->gc_canonical_indices);
    }
    if (ctx->gc_func_type_indices) {
        free(ctx->gc_func_type_indices);
    }
    if (ctx->gc_root_scratch) {
        free(ctx->gc_root_scratch);
        ctx->gc_root_scratch = NULL;
    }
    while (ctx->gc_frame_chain_head) {
        wasmoon_gc_frame_t *prev = ctx->gc_frame_chain_head->prev;
        free(ctx->gc_frame_chain_head);
        ctx->gc_frame_chain_head = prev;
    }

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

    // Free hostcall callback closure (if registered).
    if (ctx->hostcall_callback_data) {
        moonbit_decref(ctx->hostcall_callback_data);
        ctx->hostcall_callback_data = NULL;
    }
    ctx->hostcall_callback = NULL;

    // Free WASI resources (fds, args/env, stdio buffers)
    wasmoon_jit_free_wasi_fds((int64_t)ctx);

    free(ctx);
}

// ============ Context Setters ============

void ctx_refresh_memory0_fast_fields(jit_context_t *ctx) {
    if (!ctx) return;
    if (!ctx->memory0) {
        ctx->memory0_base = NULL;
        atomic_store_explicit(&ctx->memory0_size, 0, memory_order_relaxed);
        return;
    }
    ctx->memory0_base = ctx->memory0->base;
    atomic_store_explicit(
        &ctx->memory0_size,
        atomic_load_explicit(&ctx->memory0->current_length, memory_order_relaxed),
        memory_order_relaxed
    );
}

void ctx_set_func_internal(jit_context_t *ctx, int idx, void *func_ptr) {
    if (ctx && idx >= 0 && idx < ctx->func_count) {
        ctx->func_table[idx] = func_ptr;
    }
}

void ctx_set_memory_internal(jit_context_t *ctx, wasmoon_memory_t *mem0) {
    if (ctx) {
        ctx->memory0 = mem0;
        ctx_refresh_memory0_fast_fields(ctx);
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

void ctx_gc_begin_frame_internal(jit_context_t *ctx, uintptr_t frame_id) {
    if (!ctx) return;
    wasmoon_gc_frame_t *frame = (wasmoon_gc_frame_t *)malloc(sizeof(wasmoon_gc_frame_t));
    if (!frame) return;
    frame->prev = ctx->gc_frame_chain_head;
    frame->frame_id = frame_id;
    frame->table = ctx->gc_safepoint_table;
    ctx->gc_frame_chain_head = frame;
}

void ctx_gc_end_frame_internal(jit_context_t *ctx) {
    if (!ctx || !ctx->gc_frame_chain_head) return;
    wasmoon_gc_frame_t *top = ctx->gc_frame_chain_head;
    ctx->gc_frame_chain_head = top->prev;
    free(top);
}

void ctx_gc_set_safepoint_table_internal(
    jit_context_t *ctx,
    const wasmoon_gc_safepoint_table_t *table
) {
    if (!ctx) return;
    ctx->gc_safepoint_table = table;
}

int32_t ctx_gc_set_root_scratch_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
) {
    if (!ctx) {
        return 0;
    }
    if (root_count <= 0 || !roots) {
        ctx->gc_root_scratch_len = 0;
        return 1;
    }
    if (root_count > ctx->gc_root_scratch_cap) {
        int32_t new_cap = ctx->gc_root_scratch_cap > 0 ? ctx->gc_root_scratch_cap : 16;
        while (new_cap < root_count) {
            if (new_cap > INT32_MAX / 2) {
                new_cap = root_count;
                break;
            }
            new_cap *= 2;
        }
        int64_t *new_buf = (int64_t *)realloc(ctx->gc_root_scratch, (size_t)new_cap * sizeof(int64_t));
        if (!new_buf) {
            return 0;
        }
        ctx->gc_root_scratch = new_buf;
        ctx->gc_root_scratch_cap = new_cap;
    }
    memcpy(ctx->gc_root_scratch, roots, (size_t)root_count * sizeof(int64_t));
    ctx->gc_root_scratch_len = root_count;
    return 1;
}

int32_t gc_collect_for_alloc_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
) {
    if (!ctx || !ctx->gc_heap) {
        return -1;
    }
    if (ctx->gc_in_collect) {
        return -1;
    }

    GcHeap *heap = (GcHeap *)ctx->gc_heap;
    int32_t safe_root_count = root_count > 0 ? root_count : 0;
    int32_t scratch_count = ctx->gc_root_scratch_len > 0 ? ctx->gc_root_scratch_len : 0;
    int32_t exception_root_count = ctx->exception_value_count > 0 ? ctx->exception_value_count : 0;
    int32_t spilled_root_count = ctx->spilled_locals_count > 0 ? ctx->spilled_locals_count : 0;
    int32_t stack_root_count = safe_root_count + scratch_count;
    int32_t store_root_count = exception_root_count + spilled_root_count;
    int32_t total_roots = stack_root_count + store_root_count;
    int32_t collected = 0;
    size_t heap_size_before = heap->size;
    int32_t object_count_before = heap->object_count;
    int32_t free_count_before = heap->free_count;

    ctx->gc_collect_requested = 1;
    ctx->gc_in_collect = 1;

    if (total_roots > 0) {
        int64_t *merged = (int64_t *)malloc((size_t)total_roots * sizeof(int64_t));
        if (!merged) {
            ctx->gc_in_collect = 0;
            ctx->gc_collect_requested = 0;
            return -1;
        }
        int32_t at = 0;
        if (safe_root_count > 0 && roots) {
            memcpy(&merged[at], roots, (size_t)safe_root_count * sizeof(int64_t));
            at += safe_root_count;
        }
        if (scratch_count > 0 && ctx->gc_root_scratch) {
            memcpy(&merged[at], ctx->gc_root_scratch, (size_t)scratch_count * sizeof(int64_t));
            at += scratch_count;
        }
        if (exception_root_count > 0 && ctx->exception_values) {
            memcpy(&merged[at], ctx->exception_values, (size_t)exception_root_count * sizeof(int64_t));
            at += exception_root_count;
        }
        if (spilled_root_count > 0 && ctx->spilled_locals) {
            memcpy(&merged[at], ctx->spilled_locals, (size_t)spilled_root_count * sizeof(int64_t));
        }
        collected = gc_heap_collect(heap, merged, total_roots);
        free(merged);
    } else {
        collected = gc_heap_collect(heap, NULL, 0);
    }

    if (gc_collect_debug_enabled()) {
        fprintf(
            stderr,
            "[GC COLLECT] stack_roots=%d store_roots=%d total=%d collected=%d "
            "heap=%zu/%zu->%zu/%zu objs=%d->%d free=%d->%d\n",
            stack_root_count,
            store_root_count,
            total_roots,
            collected,
            heap_size_before,
            heap->capacity,
            heap->size,
            heap->capacity,
            object_count_before,
            heap->object_count,
            free_count_before,
            heap->free_count
        );
    }

    ctx->gc_in_collect = 0;
    ctx->gc_collect_requested = 0;
    ctx_update_gc_heap_ptr_internal(ctx);
    return collected;
}
