// Copyright 2025
// JIT context management
// Handles allocation, configuration, and lifecycle of jit_context_t

#include "jit_internal.h"
#include <assert.h>

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

static int32_t gc_frame_chain_depth(const jit_context_t *ctx) {
    if (!ctx) {
        return 0;
    }
    int32_t depth = 0;
    const wasmoon_gc_frame_t *cur = ctx_execution(ctx)->gc_frame_chain_head;
    while (cur) {
        depth++;
        cur = cur->prev;
    }
    return depth;
}

static int32_t gc_root_scope_count(const jit_context_t *ctx) {
    if (!ctx) {
        return 0;
    }
    int64_t total = 0;
    const wasmoon_gc_root_scope_t *scope = ctx_execution(ctx)->gc_root_scope_head;
    while (scope) {
        if (scope->root_count > 0) {
            total += scope->root_count;
            if (total > INT32_MAX) {
                return INT32_MAX;
            }
        }
        scope = scope->prev;
    }
    return (int32_t)total;
}

static int32_t gc_copy_root_scopes(
    const jit_context_t *ctx,
    int64_t *dst
) {
    if (!ctx || !dst) {
        return 0;
    }
    int32_t at = 0;
    const wasmoon_gc_root_scope_t *scope = ctx_execution(ctx)->gc_root_scope_head;
    while (scope) {
        if (scope->root_count > 0 && scope->roots) {
            memcpy(
                &dst[at],
                scope->roots,
                (size_t)scope->root_count * sizeof(int64_t)
            );
            at += scope->root_count;
        }
        scope = scope->prev;
    }
    return at;
}

static int32_t gc_count_table_roots(const jit_context_t *ctx) {
    if (!ctx) {
        return 0;
    }
    size_t total = 0;
    if (ctx->table0_base && ctx->table0_elements > 0) {
        total += ctx->table0_elements;
    }
    if (ctx->tables && ctx->table_sizes && ctx->table_count > 1) {
        for (int i = 1; i < ctx->table_count; i++) {
            if (ctx->tables[i] && ctx->table_sizes[i] > 0) {
                total += ctx->table_sizes[i];
            }
        }
    }
    if (total > (size_t)INT32_MAX) {
        return INT32_MAX;
    }
    return (int32_t)total;
}

static int32_t gc_copy_table_roots(const jit_context_t *ctx, int64_t *dst) {
    if (!ctx || !dst) {
        return 0;
    }
    int32_t at = 0;
    if (ctx->table0_base && ctx->table0_elements > 0) {
        for (size_t i = 0; i < ctx->table0_elements; i++) {
            dst[at++] = (int64_t)(uintptr_t)ctx->table0_base[i * 2];
        }
    }
    if (ctx->tables && ctx->table_sizes && ctx->table_count > 1) {
        for (int table_idx = 1; table_idx < ctx->table_count; table_idx++) {
            void **table_ptr = ctx->tables[table_idx];
            size_t table_size = ctx->table_sizes[table_idx];
            if (!table_ptr || table_size == 0) {
                continue;
            }
            for (size_t i = 0; i < table_size; i++) {
                dst[at++] = (int64_t)(uintptr_t)table_ptr[i * 2];
            }
        }
    }
    return at;
}

// ============ Context Allocation ============

// Consume a MoonBit external-pointer array. Its entries do not own code.
jit_context_t *alloc_context_with_functions(void **functions) {
    jit_context_owner_t *owner = calloc(1, sizeof(*owner));
    if (!owner) {
        moonbit_decref(functions);
        return NULL;
    }
    jit_context_t *ctx = &owner->abi;
    atomic_init(&ctx->memory0_size, 0);
    ctx->func_table = functions;
    ctx->func_count = Moonbit_array_length(functions);
    ctx->debug_current_func_idx = -1;
    return ctx;
}

jit_context_t *alloc_context_internal(int func_count) {
    if (func_count < 0) return NULL;
    return alloc_context_with_functions(moonbit_make_extern_ref_array(func_count, NULL));
}

// Descriptor addresses stay stable while their RC-owned payloads are replaced.
static void gc_release_safepoint_table(wasmoon_gc_safepoint_table_t *table) {
    if (table->stackmap_blob) moonbit_decref((void *)table->stackmap_blob);
    if (table->code_offsets) moonbit_decref((void *)table->code_offsets);
    memset(table, 0, sizeof(*table));
}

// ============ Context Free ============


void free_context_internal(jit_context_t *ctx) {
    if (!ctx) return;
    continuation_arena_release(ctx_runtime(ctx)->continuation_arena);
    continuation_types_free(ctx);
    exception_arena_release(ctx_runtime(ctx)->exception_arena);
    ctx_set_gc_heap_internal(ctx, NULL);

    ctx_clear_segments_internal(ctx);

    // Free context-owned memory0 (guarded allocations are large and must not leak)
    if (ctx_runtime(ctx)->owns_memory0 && ctx->memory0) {
        wasmoon_jit_free_memory_desc(ctx->memory0);
        ctx->memory0 = NULL;
        ctx->memory0_base = NULL;
        atomic_store_explicit(&ctx->memory0_size, 0, memory_order_relaxed);
        ctx_runtime(ctx)->owns_memory0 = 0;
    }

    if (ctx->func_table) moonbit_decref(ctx->func_table);
    ctx_clear_table_bindings(ctx);
    if (ctx->tables) free(ctx->tables);
    if (ctx->table_sizes) free(ctx->table_sizes);
    if (ctx->table_max_sizes) free(ctx->table_max_sizes);
    if (ctx->globals) free(ctx->globals);
    if (ctx_runtime(ctx)->callable_local_types)
        moonbit_decref(ctx_runtime(ctx)->callable_local_types);
    if (ctx_runtime(ctx)->callable_registry)
        moonbit_decref(ctx_runtime(ctx)->callable_registry);
    if (ctx_runtime(ctx)->callable_tags)
        moonbit_decref(ctx_runtime(ctx)->callable_tags);
    if (ctx_runtime(ctx)->gc_func_table) moonbit_decref(ctx_runtime(ctx)->gc_func_table);

    // Release each managed descriptor retained by the multi-memory array.
    if (ctx->memories) {
        for (int i = 0; i < ctx->memory_count; ++i) {
            if (ctx->memories[i]) moonbit_decref(ctx->memories[i]);
        }
        free(ctx->memories);
    }

    if (ctx_runtime(ctx)->gc_type_cache) {
        moonbit_decref(ctx_runtime(ctx)->gc_type_cache);
    }
    if (ctx_runtime(ctx)->gc_canonical_indices) {
        moonbit_decref(ctx_runtime(ctx)->gc_canonical_indices);
    }
    if (ctx_runtime(ctx)->gc_func_type_indices) {
        moonbit_decref(ctx_runtime(ctx)->gc_func_type_indices);
    }
    jit_execution_state_clear(ctx_runtime(ctx)->execution);
    free(ctx_runtime(ctx)->execution);
    ctx_runtime(ctx)->execution = NULL;
    if (ctx_runtime(ctx)->gc_func_safepoint_tables) {
        int32_t count = ctx_runtime(ctx)->gc_func_safepoint_table_count;
        for (int32_t i = 0; i < count; i++) {
            gc_release_safepoint_table(&ctx_runtime(ctx)->gc_func_safepoint_tables[i]);
        }
        free(ctx_runtime(ctx)->gc_func_safepoint_tables);
        ctx_runtime(ctx)->gc_func_safepoint_tables = NULL;
    }
    ctx_runtime(ctx)->gc_func_safepoint_table_count = 0;

    // Free hostcall callback closure (if registered).
    if (ctx_runtime(ctx)->hostcall_callback_data) {
        moonbit_decref(ctx_runtime(ctx)->hostcall_callback_data);
        ctx_runtime(ctx)->hostcall_callback_data = NULL;
    }
    ctx_runtime(ctx)->hostcall_callback = NULL;

    // Free cancellation callback closure (if registered).
    if (ctx_runtime(ctx)->control_defaults.cancellation_callback_data) {
        moonbit_decref(ctx_runtime(ctx)->control_defaults.cancellation_callback_data);
        ctx_runtime(ctx)->control_defaults.cancellation_callback_data = NULL;
    }
    ctx_runtime(ctx)->control_defaults.cancellation_callback = NULL;

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

void ctx_set_indirect_internal(jit_context_t *ctx, int table_idx, int func_idx, int type_idx) {
    if (ctx && ctx->table0_base &&
        table_idx >= 0 && (size_t)table_idx < ctx->table0_elements &&
        func_idx >= 0 && func_idx < ctx->func_count) {
        // Store func_ptr at offset 0, type_idx at offset 8
        ctx->table0_base[table_idx * 2] = ctx->func_table[func_idx];
        ctx->table0_base[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
    }
}

// ============ GC Heap Support ============

void ctx_set_gc_heap_internal(jit_context_t *ctx, GcHeap *heap) {
    if (!ctx) return;

    heap = gc_heap_live(heap);
    if (ctx->gc_heap != heap) {
        if (heap) moonbit_incref(heap);
        GcHeap *old = ctx->gc_heap;
        ctx->gc_heap = heap;
        if (old) moonbit_decref(old);
    }
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
    frame->prev = ctx_execution(ctx)->gc_frame_chain_head;
    frame->frame_id = frame_id;
    frame->table = ctx_runtime(ctx)->gc_safepoint_table;
    ctx_execution(ctx)->gc_frame_chain_head = frame;
}

void ctx_gc_end_frame_internal(jit_context_t *ctx) {
    if (!ctx || !ctx_execution(ctx)->gc_frame_chain_head) return;
    wasmoon_gc_frame_t *top = ctx_execution(ctx)->gc_frame_chain_head;
    ctx_execution(ctx)->gc_frame_chain_head = top->prev;
    free(top);
}


int32_t ctx_gc_push_root_scope_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
) {
    if (!ctx || root_count < 0 || (root_count > 0 && !roots)) {
        return 0;
    }
    wasmoon_gc_root_scope_t *scope =
        (wasmoon_gc_root_scope_t *)malloc(sizeof(wasmoon_gc_root_scope_t));
    if (!scope) {
        return 0;
    }
    scope->prev = ctx_execution(ctx)->gc_root_scope_head;
    scope->roots = NULL;
    scope->root_count = root_count;
    if (root_count > 0) {
        scope->roots = (int64_t *)malloc((size_t)root_count * sizeof(int64_t));
        if (!scope->roots) {
            free(scope);
            return 0;
        }
        memcpy(scope->roots, roots, (size_t)root_count * sizeof(int64_t));
    }
    ctx_execution(ctx)->gc_root_scope_head = scope;
    return 1;
}

void ctx_gc_pop_root_scope_internal(jit_context_t *ctx) {
    if (!ctx || !ctx_execution(ctx)->gc_root_scope_head) {
        return;
    }
    wasmoon_gc_root_scope_t *scope = ctx_execution(ctx)->gc_root_scope_head;
    ctx_execution(ctx)->gc_root_scope_head = scope->prev;
    free(scope->roots);
    free(scope);
}

void ctx_gc_restore_root_scopes_internal(
    jit_context_t *ctx,
    wasmoon_gc_root_scope_t *marker
) {
    if (!ctx) {
        return;
    }
    while (ctx_execution(ctx)->gc_root_scope_head && ctx_execution(ctx)->gc_root_scope_head != marker) {
        ctx_gc_pop_root_scope_internal(ctx);
    }
    if (marker && ctx_execution(ctx)->gc_root_scope_head != marker) {
        ctx_gc_clear_root_scopes_internal(ctx);
    }
}

void jit_execution_clear_root_scopes(jit_execution_state_t *state) {
    while (state->gc_root_scope_head) {
        wasmoon_gc_root_scope_t *scope = state->gc_root_scope_head;
        state->gc_root_scope_head = scope->prev;
        free(scope->roots);
        free(scope);
    }
}

void ctx_gc_clear_root_scopes_internal(jit_context_t *ctx) {
    if (ctx && ctx_runtime(ctx)->execution)
        jit_execution_clear_root_scopes(ctx_runtime(ctx)->execution);
}

jit_execution_state_t *ctx_execution_fallback(const jit_context_t *ctx) {
    jit_execution_state_t *state = calloc(1, sizeof(*state));
    if (!state) abort();
    ctx_runtime(ctx)->execution = state;
    return state;
}

void jit_execution_state_clear(jit_execution_state_t *state) {
    if (!state) return;
    exception_reset_execution_state(state);
    while (state->gc_frame_chain_head) {
        wasmoon_gc_frame_t *frame = state->gc_frame_chain_head;
        state->gc_frame_chain_head = frame->prev;
        free(frame);
    }
    free(state->gc_root_scratch);
    memset(state, 0, sizeof(*state));
}

void ctx_gc_set_safepoint_table_internal(
    jit_context_t *ctx,
    const wasmoon_gc_safepoint_table_t *table
) {
    if (!ctx) return;
    ctx_runtime(ctx)->gc_safepoint_table = table;
}

static int32_t gc_alloc_func_safepoint_tables(jit_context_t *ctx) {
    if (!ctx) {
        return 0;
    }
    if (ctx_runtime(ctx)->gc_func_safepoint_tables) {
        return 1;
    }
    int32_t count = ctx->func_count > 0 ? ctx->func_count : 0;
    if (count <= 0) {
        return 0;
    }
    wasmoon_gc_safepoint_table_t *tables =
        (wasmoon_gc_safepoint_table_t *)calloc((size_t)count, sizeof(wasmoon_gc_safepoint_table_t));
    if (!tables) {
        return 0;
    }
    ctx_runtime(ctx)->gc_func_safepoint_tables = tables;
    ctx_runtime(ctx)->gc_func_safepoint_table_count = count;
    return 1;
}

static int32_t bind_func_safepoints(
    jit_context_t *ctx, int32_t func_idx, uint8_t *blob, int32_t blob_size,
    int32_t *offsets, int32_t count
) {
    if (!ctx || func_idx < 0 || func_idx >= ctx->func_count ||
        !gc_alloc_func_safepoint_tables(ctx)) return 0;
    blob = blob_size ? blob : NULL;
    offsets = count ? offsets : NULL;
    // A caller may rebind exactly the currently retained payloads.
    if (blob) moonbit_incref(blob);
    if (offsets) moonbit_incref(offsets);
    wasmoon_gc_safepoint_table_t *table = &ctx_runtime(ctx)->gc_func_safepoint_tables[func_idx];
    gc_release_safepoint_table(table);
    table->stackmap_blob = blob;
    table->stackmap_blob_size = (uint32_t)blob_size;
    table->code_offsets = (uint32_t *)offsets;
    table->safepoint_count = (uint32_t)count;
    return 1;
}

// Legacy raw-pointer input is copied; it must never be passed to RC primitives.
int32_t ctx_gc_set_func_safepoints_internal(
    jit_context_t *ctx, int32_t func_idx, const uint8_t *stackmap_blob,
    int32_t stackmap_blob_size, const int32_t *code_offsets, int32_t safepoint_count
) {
    if (!ctx || func_idx < 0 || func_idx >= ctx->func_count) return 0;
    int32_t blob_size = stackmap_blob_size > 0 ? stackmap_blob_size : 0;
    int32_t count = safepoint_count > 0 ? safepoint_count : 0;
    uint8_t *blob = moonbit_make_bytes(blob_size, 0);
    int32_t *offsets = moonbit_make_int32_array(count, 0);
    if (blob_size && stackmap_blob) memcpy(blob, stackmap_blob, (size_t)blob_size);
    if (count && code_offsets) memcpy(offsets, code_offsets, (size_t)count * sizeof(int32_t));
    int32_t result = bind_func_safepoints(ctx, func_idx, blob, blob_size, offsets, count);
    moonbit_decref(blob);
    moonbit_decref(offsets);
    return result;
}

void ctx_gc_use_func_safepoints_internal(
    jit_context_t *ctx,
    int32_t func_idx
) {
    if (!ctx || !ctx_runtime(ctx)->gc_func_safepoint_tables) {
        if (ctx) {
            ctx_runtime(ctx)->gc_safepoint_table = NULL;
        }
        return;
    }
    if (func_idx < 0 || func_idx >= ctx_runtime(ctx)->gc_func_safepoint_table_count) {
        ctx_runtime(ctx)->gc_safepoint_table = NULL;
        return;
    }
    wasmoon_gc_safepoint_table_t *table = &ctx_runtime(ctx)->gc_func_safepoint_tables[func_idx];
    if (table->safepoint_count == 0 && table->stackmap_blob_size == 0) {
        ctx_runtime(ctx)->gc_safepoint_table = NULL;
    } else {
        ctx_runtime(ctx)->gc_safepoint_table = table;
    }
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
        ctx_execution(ctx)->gc_root_scratch_len = 0;
        return 1;
    }
    if (root_count > ctx_execution(ctx)->gc_root_scratch_cap) {
        int32_t new_cap = ctx_execution(ctx)->gc_root_scratch_cap > 0 ? ctx_execution(ctx)->gc_root_scratch_cap : 16;
        while (new_cap < root_count) {
            if (new_cap > INT32_MAX / 2) {
                new_cap = root_count;
                break;
            }
            new_cap *= 2;
        }
        int64_t *new_buf = (int64_t *)realloc(ctx_execution(ctx)->gc_root_scratch, (size_t)new_cap * sizeof(int64_t));
        if (!new_buf) {
            return 0;
        }
        ctx_execution(ctx)->gc_root_scratch = new_buf;
        ctx_execution(ctx)->gc_root_scratch_cap = new_cap;
    }
    memcpy(ctx_execution(ctx)->gc_root_scratch, roots, (size_t)root_count * sizeof(int64_t));
    ctx_execution(ctx)->gc_root_scratch_len = root_count;
    return 1;
}

int32_t gc_collect_for_alloc_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
) {
    jit_context_t *activation = get_current_jit_context();
    if (activation && ctx && activation->gc_heap == ctx->gc_heap) ctx = activation;
    if (!ctx || !ctx->gc_heap) {
        return -1;
    }
    if (ctx_execution(ctx)->gc_in_collect) {
        return -1;
    }

    GcHeap *heap = (GcHeap *)ctx->gc_heap;
    int32_t safe_root_count = root_count > 0 ? root_count : 0;
    int32_t scratch_count = ctx_execution(ctx)->gc_root_scratch_len > 0 ? ctx_execution(ctx)->gc_root_scratch_len : 0;
    int32_t caller_root_count = gc_root_scope_count(ctx);
    int32_t exception_root_count = ctx_execution(ctx)->exception_value_count > 0 ? ctx_execution(ctx)->exception_value_count : 0;
    int32_t spilled_root_count = ctx_execution(ctx)->spilled_locals_count > 0 ? ctx_execution(ctx)->spilled_locals_count : 0;
    int32_t table_root_count = gc_count_table_roots(ctx);
    int64_t stack_root_count64 =
        (int64_t)safe_root_count +
        scratch_count +
        caller_root_count;
    int64_t store_root_count64 =
        (int64_t)exception_root_count + spilled_root_count;
    int64_t total_roots64 =
        stack_root_count64 + store_root_count64 + table_root_count;
    if (stack_root_count64 > INT32_MAX ||
        store_root_count64 > INT32_MAX ||
        total_roots64 > INT32_MAX) {
        return -1;
    }
    int32_t stack_root_count = (int32_t)stack_root_count64;
    int32_t store_root_count = (int32_t)store_root_count64;
    int32_t total_roots = (int32_t)total_roots64;
    int32_t collected = 0;
    const wasmoon_gc_safepoint_table_t *active_table = ctx_runtime(ctx)->gc_safepoint_table;
    if (ctx_execution(ctx)->gc_frame_chain_head && ctx_execution(ctx)->gc_frame_chain_head->table) {
        active_table = ctx_execution(ctx)->gc_frame_chain_head->table;
    }
    size_t heap_size_before = heap->size;
    int32_t object_count_before = heap->object_count;
    int32_t free_count_before = heap->free_count;

    ctx_execution(ctx)->gc_collect_requested = 1;
    ctx_execution(ctx)->gc_in_collect = 1;

    if (total_roots > 0) {
        int64_t *merged = (int64_t *)malloc((size_t)total_roots * sizeof(int64_t));
        if (!merged) {
            ctx_execution(ctx)->gc_in_collect = 0;
            ctx_execution(ctx)->gc_collect_requested = 0;
            return -1;
        }
        int32_t at = 0;
        if (safe_root_count > 0 && roots) {
            memcpy(&merged[at], roots, (size_t)safe_root_count * sizeof(int64_t));
            at += safe_root_count;
        }
        if (scratch_count > 0 && ctx_execution(ctx)->gc_root_scratch) {
            memcpy(&merged[at], ctx_execution(ctx)->gc_root_scratch, (size_t)scratch_count * sizeof(int64_t));
            at += scratch_count;
        }
        if (caller_root_count > 0) {
            at += gc_copy_root_scopes(ctx, &merged[at]);
        }
        if (exception_root_count > 0 && ctx_execution(ctx)->exception_values) {
            memcpy(&merged[at], ctx_execution(ctx)->exception_values, (size_t)exception_root_count * sizeof(int64_t));
            at += exception_root_count;
        }
        if (spilled_root_count > 0 && ctx_execution(ctx)->spilled_locals) {
            memcpy(&merged[at], ctx_execution(ctx)->spilled_locals, (size_t)spilled_root_count * sizeof(int64_t));
            at += spilled_root_count;
        }
        if (table_root_count > 0) {
            at += gc_copy_table_roots(ctx, &merged[at]);
        }
        jit_mark_active_gc_roots(heap);
        collected = gc_heap_collect(heap, merged, total_roots);
        free(merged);
    } else {
        jit_mark_active_gc_roots(heap);
        collected = gc_heap_collect(heap, NULL, 0);
    }

    if (gc_collect_debug_enabled()) {
        fprintf(
            stderr,
            "[GC COLLECT] stack_roots=%d store_roots=%d table_roots=%d total=%d collected=%d "
            "heap=%zu/%zu->%zu/%zu objs=%d->%d free=%d->%d\n",
            stack_root_count,
            store_root_count,
            table_root_count,
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
        fprintf(
            stderr,
            "[GC COLLECT] frame_depth=%d safepoint_table=%s safepoints=%u stackmap=%u\n",
            gc_frame_chain_depth(ctx),
            active_table ? "set" : "none",
            active_table ? active_table->safepoint_count : 0,
            active_table ? active_table->stackmap_blob_size : 0
        );
    }

    ctx_execution(ctx)->gc_in_collect = 0;
    ctx_execution(ctx)->gc_collect_requested = 0;
    ctx_update_gc_heap_ptr_internal(ctx);
    return collected;
}

void ctx_clear_table_bindings(jit_context_t *ctx) {
    if (!ctx_runtime(ctx)->table_bindings) return;
    for (int i = 0; i < ctx->table_count; ++i) {
        wasmoon_table_binding_t *binding = &ctx_runtime(ctx)->table_bindings[i];
        wasmoon_table_t *owner = binding->owner;
        if (binding->previous) binding->previous->next = binding->next;
        else owner->bindings = binding->next;
        if (binding->next) binding->next->previous = binding->previous;
        moonbit_decref(owner);
    }
    free(ctx_runtime(ctx)->table_bindings);
    ctx_runtime(ctx)->table_bindings = NULL;
}

void table_publish_layout(wasmoon_table_t *table, void **entries, size_t size) {
    table->entries = entries;
    table->size = size;
    for (wasmoon_table_binding_t *binding = table->bindings; binding; binding = binding->next) {
        jit_context_t *ctx = binding->context;
        ctx->tables[binding->index] = entries;
        ctx->table_sizes[binding->index] = size;
        if (binding->index == 0) {
            ctx->table0_base = entries;
            ctx->table0_elements = size;
        }
    }
}

// Compiler layout is derived from the native declarations, once at startup.
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_layout_field(int32_t index) {
    static const int32_t fields[] = {
        offsetof(jit_context_t, memory0),
        offsetof(jit_context_t, memory0_base),
        offsetof(jit_context_t, memory0_size),
        offsetof(jit_context_t, func_table),
        offsetof(jit_context_t, table0_base),
        offsetof(jit_context_t, table0_elements),
        offsetof(jit_context_t, globals),
        offsetof(jit_context_t, tables),
        offsetof(jit_context_t, table_count),
        offsetof(jit_context_t, func_count),
        offsetof(jit_context_t, table_sizes),
        offsetof(jit_context_t, table_max_sizes),
        offsetof(jit_context_t, memories),
        offsetof(jit_context_t, memory_count),
        offsetof(jit_context_t, debug_current_func_idx),
        offsetof(jit_context_t, gc_heap_ptr),
        offsetof(jit_context_t, gc_heap_limit),
        offsetof(jit_context_t, gc_heap),
        sizeof(void *),
        sizeof(int64_t),
        0,
        2 * sizeof(void *),
        sizeof(void *),
        offsetof(wasmoon_memory_t, base),
        offsetof(wasmoon_memory_t, current_length),
    };
    assert(index >= 0 && (size_t)index < sizeof(fields) / sizeof(fields[0]));
    return fields[index];
}

// Managed callable binding shares the context lifecycle translation unit.
extern int64_t wasmoon_jit_context_ptr(void *context);

MOONBIT_FFI_EXPORT void wasmoon_jit_bind_callable_registry(
    void *managed_context, void *registry,
    int32_t *local_types, int32_t local_count,
    int32_t *tags, int32_t tag_count
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(managed_context);
    if (!ctx) return;
    // Preserve the legacy empty-local-map fallback while retaining nonempty arrays.
    int32_t *locals = local_count ? local_types : NULL;
    int32_t *tag_map = tag_count ? tags : NULL;
    moonbit_incref(registry);
    if (locals) moonbit_incref(locals);
    if (tag_map) moonbit_incref(tag_map);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    if (state->callable_registry) moonbit_decref(state->callable_registry);
    if (state->callable_local_types) moonbit_decref(state->callable_local_types);
    if (state->callable_tags) moonbit_decref(state->callable_tags);
    state->callable_registry = registry;
    state->callable_local_types = locals;
    state->callable_local_type_count = local_count;
    state->callable_tags = tag_map;
    state->callable_tag_count = tag_count;
}

// The MoonBit owner prepares typed arrays. Native helpers only retain/read them.
MOONBIT_FFI_EXPORT void wasmoon_jit_bind_gc_metadata(
    void *managed_context, int32_t *types, int32_t *canonical, int32_t *functions
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(managed_context);
    if (!ctx) return;
    int32_t type_slots = Moonbit_array_length(types);
    int32_t canonical_count = Moonbit_array_length(canonical);
    int32_t function_count = Moonbit_array_length(functions);
    // Retain all inputs first, including aliases of the currently bound arrays.
    types = type_slots ? types : NULL;
    canonical = canonical_count ? canonical : NULL;
    functions = function_count ? functions : NULL;
    if (types) moonbit_incref(types);
    if (canonical) moonbit_incref(canonical);
    if (functions) moonbit_incref(functions);
    jit_runtime_state_t *state = ctx_runtime(ctx);
    if (state->gc_type_cache) moonbit_decref(state->gc_type_cache);
    if (state->gc_canonical_indices) moonbit_decref(state->gc_canonical_indices);
    if (state->gc_func_type_indices) moonbit_decref(state->gc_func_type_indices);
    state->gc_type_cache = types;
    state->gc_num_types = type_slots / GC_TYPE_CACHE_STRIDE;
    state->gc_canonical_indices = canonical;
    state->gc_num_canonical = canonical_count;
    state->gc_func_type_indices = functions;
    state->gc_num_funcs = function_count;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_bind_gc_safepoints(
    void *context, int32_t function, uint8_t *blob, int32_t *offsets
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    return bind_func_safepoints(ctx, function, blob, Moonbit_array_length(blob),
        offsets, Moonbit_array_length(offsets));
}

MOONBIT_FFI_EXPORT void wasmoon_jit_bind_gc_function_addresses(
    void *context, int64_t *addresses
) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(context);
    if (!ctx) return;
    int32_t count = Moonbit_array_length(addresses);
    addresses = count ? addresses : NULL;
    if (addresses) moonbit_incref(addresses);
    if (ctx_runtime(ctx)->gc_func_table) moonbit_decref(ctx_runtime(ctx)->gc_func_table);
    ctx_runtime(ctx)->gc_func_table = addresses;
    ctx_runtime(ctx)->gc_func_table_size = count;
}
