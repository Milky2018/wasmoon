// Copyright 2025
// GC operations for JIT runtime
// Implements struct.new/get/set, array.new/get/set/len/fill/copy

#include "jit_internal.h"
#include "gc_allocator.h"
#include "gc_access.h"

// ============ Value Decoding Helpers ============

static inline int32_t decode_heap_ref(int64_t val) {
    return (int32_t)(val >> 1);
}

static inline jit_context_t *resolve_ctx(jit_context_t *ctx) {
    if (ctx) return ctx;
    return get_current_jit_context_fast();
}

static inline GcHeap *resolve_heap(jit_context_t *ctx) {
    jit_context_t *actual = resolve_ctx(ctx);
    if (!actual || !ctx_gc_heap(actual)) return NULL;
    return (GcHeap *)ctx_gc_heap(actual);
}

static int64_t trap_allocation_too_large(void) {
    g_trap_code = WASMOON_TRAP_ALLOCATION_TOO_LARGE;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    return 0;
}

static int array_length_exceeds_layout(int32_t len) {
    return len < 0 || (uint64_t)(uint32_t)len > (INT32_MAX - 32U) / 16U;
}

static int64_t trap_null_reference(void) {
    g_trap_code = WASMOON_TRAP_NULL_REFERENCE;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    return 0;
}

static int64_t trap_unreachable_i64(void) {
    g_trap_code = 3;
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return 0;
}

static int32_t trap_unreachable_i32(void) {
    g_trap_code = 3;
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return 0;
}

static void trap_unreachable_void(void) {
    g_trap_code = 3;
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
}

static int64_t trap_out_of_memory_i64(void) {
    g_trap_code = 9;
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return 0;
}

static int64_t trap_gc_allocation_i64(int32_t result) {
    g_trap_code = -result;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    return 0;
}

static int64_t trap_gc_precise_roots_i64(void) {
    g_trap_code = 10;
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return 0;
}

static int gc_alloc_debug_cached = -1;

static int gc_is_truthy_env(const char *value) {
    if (!value) return 0;
    return strcmp(value, "1") == 0 ||
           strcmp(value, "true") == 0 ||
           strcmp(value, "TRUE") == 0 ||
           strcmp(value, "yes") == 0 ||
           strcmp(value, "YES") == 0 ||
           strcmp(value, "on") == 0 ||
           strcmp(value, "ON") == 0;
}

static int gc_alloc_debug_enabled(void) {
    if (gc_alloc_debug_cached < 0) {
        gc_alloc_debug_cached = gc_is_truthy_env(getenv("WASMOON_GC_ALLOC_DEBUG")) ? 1 : 0;
    }
    return gc_alloc_debug_cached;
}

static void gc_log_alloc_retry(const char *op, const gc_alloc_result_t *result) {
    if (!gc_alloc_debug_enabled() || !result) {
        return;
    }
    if (result->retry_count <= 0) {
        return;
    }
    fprintf(
        stderr,
        "[GC ALLOC] %s retries=%d collected=%d\n",
        op,
        result->retry_count,
        result->collected_objects
    );
}

static const wasmoon_gc_safepoint_table_t *gc_func_safepoint_table_for_current(
    jit_context_t *ctx
) {
    if (!ctx || !ctx_runtime(ctx)->gc_func_safepoint_tables) {
        return NULL;
    }
    int32_t func_idx = ctx_debug_current_func_idx(ctx);
    if (func_idx < 0 || func_idx >= ctx_runtime(ctx)->gc_func_safepoint_table_count) {
        return NULL;
    }
    const wasmoon_gc_safepoint_table_t *table = &ctx_runtime(ctx)->gc_func_safepoint_tables[func_idx];
    if (!table->stackmap_blob || table->stackmap_blob_size < 8) {
        return NULL;
    }
    return table;
}

static const wasmoon_gc_safepoint_table_t *gc_active_safepoint_table(jit_context_t *ctx) {
    if (!ctx) {
        return NULL;
    }
    const wasmoon_gc_safepoint_table_t *table = gc_func_safepoint_table_for_current(ctx);
    if (table) {
        return table;
    }
    table = ctx_runtime(ctx)->gc_safepoint_table;
    jit_execution_state_t *state = ctx_runtime(ctx)->execution;
    if (state && state->gc_frame_chain_head && state->gc_frame_chain_head->table) {
        table = state->gc_frame_chain_head->table;
    }
    return table;
}

static int gc_alloc_debug_enabled(void);

static void gc_log_precise_root_failure(
    const char *op,
    int32_t safepoint_id,
    const char *reason
) {
    if (!gc_alloc_debug_enabled()) {
        return;
    }
    fprintf(
        stderr,
        "[GC ROOTS] %s safepoint=%d precise-root selection failed: %s\n",
        op,
        safepoint_id,
        reason ? reason : "unknown"
    );
}

// Descriptors were validated at binding. Borrow the staged operand buffer and
// its index list; only a collection needs to enumerate/copy selected values.
static int32_t gc_select_alloc_roots(
    const char *op, jit_context_t *ctx, int32_t safepoint_id,
    int32_t function_index, const int64_t *roots, int32_t operand_count,
    const int64_t **selected_roots_out, const uint8_t **indices_out
) {
    *selected_roots_out = roots;
    *indices_out = NULL;
    if (!roots || operand_count <= 0) return 0;
    if (safepoint_id < 0) return operand_count;
    if (!ctx) {
        gc_log_precise_root_failure(op, safepoint_id, "missing jit context");
        return -1;
    }
    const wasmoon_gc_safepoint_table_t *table =
        function_index >= 0 && function_index < ctx_runtime(ctx)->gc_func_safepoint_table_count
        ? &ctx_runtime(ctx)->gc_func_safepoint_tables[function_index]
        : gc_active_safepoint_table(ctx);
    if (!table || !table->allocation_roots ||
        (uint32_t)safepoint_id >= table->safepoint_count) {
        gc_log_precise_root_failure(op, safepoint_id, "missing allocation descriptor");
        return -1;
    }
    const uint32_t *record = table->allocation_roots + (size_t)safepoint_id * 3;
    uint32_t count = record[0] < (uint32_t)operand_count ?
        record[0] : (uint32_t)operand_count;
    if (count && (record[1] == UINT32_MAX ||
        table->allocation_roots[record[1] + count - 1] >= (uint32_t)operand_count)) {
        gc_log_precise_root_failure(op, safepoint_id, "root operand index out of bounds");
        return -1;
    }
    if (count) *indices_out = table->stackmap_blob + record[2];
    return (int32_t)count;
}

// ============ Struct Operations ============

int64_t WASMOON_GUEST_ABI gc_struct_new_impl(int32_t type_idx, int64_t *fields, int32_t num_fields) {
    jit_context_t *ctx = get_current_jit_context_fast();
    GcHeap *heap = resolve_heap(ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    // Handle struct.new_default: num_fields == 0 means use default values
    int64_t *actual_fields = fields;
    int32_t actual_num_fields = num_fields;
    int64_t *default_fields = NULL;

    if (
        num_fields == 0 &&
        ctx &&
        ctx_runtime(ctx)->gc_type_cache &&
        type_idx >= 0 &&
        type_idx < ctx_runtime(ctx)->gc_num_types
    ) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields = ctx_runtime(ctx)->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_STRUCT_NUM_FIELDS_OFF];
        if (actual_num_fields > 0) {
            // Allocate and zero-initialize default fields
            default_fields = (int64_t *)calloc((size_t)actual_num_fields, sizeof(int64_t));
            if (!default_fields) {
                return trap_out_of_memory_i64();
            }
            actual_fields = default_fields;
        }
    }

    gc_allocation_request_t request = {
        .ctx = ctx, .heap = heap, .layout = GC_ALLOC_STRUCT_WORDS,
        .type_idx = type_idx, .values = actual_fields, .count = actual_num_fields,
        .init = {0, 0}, .roots = actual_fields, .root_count = actual_num_fields
    };
    int32_t gc_ref = gc_allocate(&request);

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }
    gc_log_alloc_retry("struct.new", &request.result);

    if (ctx) {
        ctx_set_gc_heap(ctx, heap);
        ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    }

    // Encode for JIT: gc_ref << 1 (1-based gc_ref stays 1-based, just shifted)
    // This ensures gc_ref=1 becomes value=2, which doesn't conflict with null (0)
    return ((int64_t)gc_ref) << 1;
}

int64_t WASMOON_GUEST_ABI gc_struct_get_impl(int64_t ref, int32_t type_idx, int32_t field_idx) {
    (void)type_idx;
    return gc_struct_get_heap_impl(resolve_heap(NULL), ref, field_idx);
}

void WASMOON_GUEST_ABI gc_struct_set_impl(int64_t ref, int32_t type_idx, int32_t field_idx, int64_t value) {
    (void)type_idx;
    gc_struct_set_heap_impl(resolve_heap(NULL), ref, field_idx, value);
}

// ============ Array Operations ============

int64_t WASMOON_GUEST_ABI gc_array_new_impl(int32_t type_idx, int32_t len, int64_t fill) {
    if (array_length_exceeds_layout(len)) return trap_allocation_too_large();
    jit_context_t *ctx = resolve_ctx(NULL);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    int64_t roots_buf[1] = { fill };
    gc_allocation_request_t request = {
        .ctx = ctx, .heap = heap, .layout = GC_ALLOC_ARRAY_WORD,
        .type_idx = type_idx, .values = NULL, .count = len,
        .init = {fill, 0}, .roots = roots_buf, .root_count = 1
    };
    int32_t gc_ref = gc_allocate(&request);
    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }
    gc_log_alloc_retry("array.new", &request.result);

    if (ctx) {
        ctx_set_gc_heap(ctx, heap);
        ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    }

    // Encode: gc_ref << 1 (1-based gc_ref, ensures gc_ref=1 -> value=2)
    return ((int64_t)gc_ref) << 1;
}

int64_t WASMOON_GUEST_ABI gc_array_get_impl(int64_t ref, int32_t type_idx, int32_t idx) {
    (void)type_idx;
    return gc_array_get_heap_impl(resolve_heap(NULL), ref, idx);
}

void WASMOON_GUEST_ABI gc_array_set_impl(int64_t ref, int32_t type_idx, int32_t idx, int64_t value) {
    (void)type_idx;
    gc_array_set_heap_impl(resolve_heap(NULL), ref, idx, value);
}

int32_t WASMOON_GUEST_ABI gc_array_len_impl(int64_t ref) {
    return gc_array_len_heap_impl(resolve_heap(NULL), ref);
}

void WASMOON_GUEST_ABI gc_array_fill_impl(int64_t ref, int32_t offset, int64_t value, int32_t count) {
    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        trap_unreachable_void();
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = WASMOON_TRAP_NULL_REFERENCE;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);

    // Bounds check
    int32_t len = gc_access_array_len(heap, gc_ref);
    if (offset < 0 || count < 0 || (int64_t)offset + count > len) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_fill(heap, gc_ref, offset, value, count);
}

void WASMOON_GUEST_ABI gc_array_copy_impl(
    int64_t dst_ref,
    int32_t dst_offset,
    int64_t src_ref,
    int32_t src_offset,
    int32_t count
) {
    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        trap_unreachable_void();
        return;
    }

    // Check for null references (encoded as 0)
    if (dst_ref == 0 || src_ref == 0) {
        g_trap_code = WASMOON_TRAP_NULL_REFERENCE;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t dst_gc_ref = decode_heap_ref(dst_ref);
    int32_t src_gc_ref = decode_heap_ref(src_ref);

    // Bounds check
    int32_t dst_len = gc_heap_array_len(heap, dst_gc_ref);
    int32_t src_len = gc_heap_array_len(heap, src_gc_ref);
    if (
        dst_offset < 0 || src_offset < 0 || count < 0 ||
        (int64_t)dst_offset + count > dst_len || (int64_t)src_offset + count > src_len
    ) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_copy(heap, dst_gc_ref, dst_offset, src_gc_ref, src_offset, count);
}

// ============ Inline Allocation Support ============

// Reserve an already available typed struct without collecting, growing or
// invoking managed code. Atomic quotas and identity publication stay in the
// shared allocator. The compiler immediately initializes the admitted bytes;
// no call/safepoint may occur in that initialization interval. Reference fields
// use the canonical layout's tracing metadata. Like gc_heap_alloc_typed, fresh
// initialization needs no mutation barrier in this stop-the-world collector.
int64_t WASMOON_GUEST_ABI gc_reserve_struct_fast_impl(jit_context_t *ctx,
    int32_t local_type, int32_t count, uint64_t shape, int32_t total_size, int64_t *ticket) {
    ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap || !ticket || count < 0 || count > 16 || !gc_heap_fast_allocation_enabled() ||
        !ctx_runtime(ctx)->callable_local_types || local_type < 0 ||
        local_type >= ctx_runtime(ctx)->callable_local_type_count) return 0;
    int32_t identity = ctx_runtime(ctx)->callable_local_types[local_type];
    GcTypeLayout *layout = gc_heap_layout(heap, identity);
    if (!layout || layout->kind != GC_KIND_STRUCT || layout->count != count ||
        total_size != ((GC_HEADER_SIZE + layout->size + 15) & -16)) return 0;
    if (layout->prefix_shape != shape) return 0;
    if (heap->size >= heap->collection_limit || total_size < 16 ||
        heap->size > (size_t)INT32_MAX - (size_t)total_size ||
        heap->size + (size_t)total_size > heap->capacity || heap->object_count == INT32_MAX ||
        heap->live_count >= heap->live_capacity) return 0;
    int32_t page_index = heap->object_count >> GC_ID_PAGE_BITS;
    if (page_index >= heap->identity_page_capacity || !heap->identity_pages[page_index]) return 0;
    // No allocation/retry occurs after admission. Denial leaves reservations
    // unchanged and the checked slow path reports the established quota error.
    if (!gc_heap_admit(heap, (size_t)total_size)) return 0;
    (void)gc_should_fail_allocation(); // Enabled above excludes injected failure.
    int32_t offset = (int32_t)heap->size;
    heap->size += (size_t)total_size;
    int32_t ref = gc_heap_register_object(heap, offset);
    gc_heap_set_runtime_type(heap, ref, identity);
    ticket[0] = (int64_t)(uintptr_t)(heap->data + offset);
    ticket[1] = (int64_t)(((uint64_t)(identity + 1) << 32) | (uint32_t)count);
    ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
    ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    return (int64_t)ref << 1;
}

// Register a struct that was allocated inline by JIT code
// obj_ptr points to the object in the heap (header already initialized)
// Returns encoded gc_ref
int64_t WASMOON_GUEST_ABI gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size) {
    (void)total_size;
    jit_context_t *actual_ctx = resolve_ctx(ctx);
    if (!actual_ctx || !ctx_gc_heap(actual_ctx) || !obj_ptr) {
        return trap_unreachable_i64();
    }

    GcHeap *heap = (GcHeap *)ctx_gc_heap(actual_ctx);

    if (!gc_heap_ensure_object_capacity(heap)) return trap_out_of_memory_i64();

    // Calculate offset and register object
    int32_t offset = (int32_t)(obj_ptr - heap->data);
    int32_t gc_ref = gc_heap_register_object(heap, offset);

    // Update heap size to match what JIT allocated
    heap->size = (size_t)(ctx_gc_heap_ptr(actual_ctx) - heap->data);

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Slow path for struct allocation - called when inline check fails
// Triggers GC if needed, grows heap, and allocates
int64_t WASMOON_GUEST_ABI gc_alloc_struct_slow(
    jit_context_t *ctx,
    int32_t type_idx,
    int64_t *fields,
    int32_t num_fields,
    int32_t safepoint_id,
    int32_t function_index
) {
    jit_context_t *actual_ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(actual_ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    // Handle struct.new_default: num_fields == 0 means use default values
    int64_t *actual_fields = fields;
    int32_t actual_num_fields = num_fields;
    int64_t *default_fields = NULL;

    if (
        num_fields == 0 &&
        actual_ctx &&
        ctx_runtime(actual_ctx)->gc_type_cache &&
        type_idx >= 0 &&
        type_idx < ctx_runtime(actual_ctx)->gc_num_types
    ) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields =
            ctx_runtime(actual_ctx)->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_STRUCT_NUM_FIELDS_OFF];
        if (actual_num_fields > 0) {
            // Allocate and zero-initialize default fields
            default_fields = (int64_t *)calloc((size_t)actual_num_fields, sizeof(int64_t));
            if (!default_fields) {
                return trap_out_of_memory_i64();
            }
            actual_fields = default_fields;
        }
    }

    const int64_t *alloc_roots = NULL;
    const uint8_t *alloc_root_indices = NULL;
    int32_t alloc_root_count = gc_select_alloc_roots(
        "alloc_struct_slow",
        actual_ctx,
        safepoint_id,
        function_index,
        fields,
        num_fields,
        &alloc_roots,
        &alloc_root_indices
    );
    if (alloc_root_count < 0) {
        if (default_fields) {
            free(default_fields);
        }
        return trap_gc_precise_roots_i64();
    }

    gc_allocation_request_t request = {
        .ctx = actual_ctx, .heap = heap, .layout = GC_ALLOC_STRUCT_WORDS,
        .type_idx = type_idx, .values = actual_fields, .count = actual_num_fields,
        .init = {0, 0}, .roots = alloc_roots, .root_count = alloc_root_count,
        .root_indices = alloc_root_indices
    };
    int32_t gc_ref = gc_allocate(&request);

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }
    gc_log_alloc_retry("alloc_struct_slow", &request.result);

    // Update VMContext heap pointers if ctx is available (heap may have grown)
    if (actual_ctx) {
        ctx_set_gc_heap(actual_ctx, heap);
        ctx_set_gc_heap_ptr(actual_ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(actual_ctx, gc_heap_allocation_limit(heap));
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Register an array that was allocated inline by JIT code
int64_t WASMOON_GUEST_ABI gc_register_array_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size) {
    // Same as struct registration - just register in object table
    return gc_register_struct_inline(ctx, obj_ptr, total_size);
}

// These entry points do not collect or register roots. Refusal must leave the
// complete allocation to the checked slow path, including its trap ordering.
static int64_t try_array(jit_context_t *ctx, int32_t type, int32_t len, GcSlot init) {
    if (array_length_exceeds_layout(len)) return 0;
    ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap || !ctx || !ctx_runtime(ctx)->callable_local_types || type < 0 ||
        type >= ctx_runtime(ctx)->callable_local_type_count) return 0;
    int32_t identity = ctx_runtime(ctx)->callable_local_types[type];
    int32_t ref = gc_heap_try_array(heap, identity, type, len, init);
    if (!ref) return 0;
    ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
    ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    return (int64_t)ref << 1;
}

int64_t WASMOON_GUEST_ABI gc_try_array_impl(jit_context_t *ctx, int32_t type,
    int32_t len, int64_t init) {
    return try_array(ctx, type, len, (GcSlot){init, 0});
}

int64_t WASMOON_GUEST_ABI gc_try_array_wide_impl(jit_context_t *ctx, int32_t type,
    int32_t len, const GcSlot *init) {
    return try_array(ctx, type, len, *init);
}

// Slow path for array allocation
int64_t WASMOON_GUEST_ABI gc_alloc_array_slow(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t len,
    int64_t init_value,
    int32_t safepoint_id,
    int32_t function_index
) {
    if (array_length_exceeds_layout(len)) return trap_allocation_too_large();
    jit_context_t *actual_ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(actual_ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    if (gc_alloc_debug_enabled()) {
        fprintf(
            stderr,
            "[GC ALLOC] alloc_array_slow enter type=%d len=%d init=%lld safepoint=%d ctx=%p actual_ctx=%p\n",
            type_idx,
            len,
            (long long)init_value,
            safepoint_id,
            (void *)ctx,
            (void *)actual_ctx
        );
    }

    int64_t roots_buf[1] = { init_value };
    const int64_t *alloc_roots = NULL;
    const uint8_t *alloc_root_indices = NULL;
    int32_t alloc_root_count = gc_select_alloc_roots(
        "alloc_array_slow",
        actual_ctx,
        safepoint_id,
        function_index,
        roots_buf,
        1,
        &alloc_roots,
        &alloc_root_indices
    );
    if (alloc_root_count < 0) {
        if (gc_alloc_debug_enabled()) {
            fprintf(stderr, "[GC ALLOC] alloc_array_slow precise roots unavailable\n");
        }
        return trap_gc_precise_roots_i64();
    }

    gc_allocation_request_t request = {
        .ctx = actual_ctx, .heap = heap, .layout = GC_ALLOC_ARRAY_WORD,
        .type_idx = type_idx, .values = NULL, .count = len,
        .init = {init_value, 0}, .roots = alloc_roots, .root_count = alloc_root_count,
        .root_indices = alloc_root_indices
    };
    int32_t gc_ref = gc_allocate(&request);
    if (gc_ref < 0) {
        if (gc_alloc_debug_enabled()) {
            fprintf(stderr, "[GC ALLOC] alloc_array_slow failed after retries\n");
        }
        return trap_gc_allocation_i64(gc_ref);
    }
    gc_log_alloc_retry("alloc_array_slow", &request.result);

    // Update VMContext heap pointers if ctx is available (heap may have grown)
    if (actual_ctx) {
        ctx_set_gc_heap(actual_ctx, heap);
        ctx_set_gc_heap_ptr(actual_ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(actual_ctx, gc_heap_allocation_limit(heap));
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Slow path for fixed array allocation from an explicit values buffer.
int64_t WASMOON_GUEST_ABI gc_alloc_array_from_values_slow(
    jit_context_t *ctx,
    int32_t type_idx,
    int64_t *values,
    int32_t len,
    int32_t safepoint_id,
    int32_t function_index
) {
    if (array_length_exceeds_layout(len)) return trap_allocation_too_large();
    jit_context_t *actual_ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(actual_ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    const int64_t *alloc_roots = NULL;
    const uint8_t *alloc_root_indices = NULL;
    int32_t alloc_root_count = gc_select_alloc_roots(
        "alloc_array_from_values_slow",
        actual_ctx,
        safepoint_id,
        function_index,
        values,
        len,
        &alloc_roots,
        &alloc_root_indices
    );
    if (alloc_root_count < 0) {
        return trap_gc_precise_roots_i64();
    }

    gc_allocation_request_t request = {
        .ctx = actual_ctx, .heap = heap, .layout = GC_ALLOC_ARRAY_WORDS,
        .type_idx = type_idx, .values = values, .count = len,
        .init = {0, 0}, .roots = alloc_roots, .root_count = alloc_root_count,
        .root_indices = alloc_root_indices
    };
    int32_t gc_ref = gc_allocate(&request);
    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }
    gc_log_alloc_retry("alloc_array_from_values_slow", &request.result);

    if (actual_ctx) {
        ctx_set_gc_heap(actual_ctx, heap);
        ctx_set_gc_heap_ptr(actual_ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(actual_ctx, gc_heap_allocation_limit(heap));
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// ============ v128 Aggregate Operations ============
//
// A v128 does not fit the int64_t runtime word the ops above are built on, so
// these carry it through a caller-owned 16-byte buffer instead. JIT-emitted
// code allocates that buffer as a stack object and passes its address, which
// keeps the call ABI to plain words and needs no 128-bit return convention.
//
// Layout of the buffer is GcSlot: low 8 bytes then high 8 bytes, little-endian.

void WASMOON_GUEST_ABI gc_struct_get_v128_impl(int64_t ref, int32_t type_idx, int32_t field_idx,
                             int64_t out_ptr) {
    (void)type_idx;

    GcSlot *out = (GcSlot *)(uintptr_t)out_ptr;
    GcHeap *heap = resolve_heap(NULL);
    if (!heap || ref == 0) {
        if (ref == 0) trap_null_reference();
        else trap_unreachable_void();
        return;
    }

    int32_t gc_ref = decode_heap_ref(ref);
    *out = gc_heap_struct_get_wide(heap, gc_ref, field_idx);
}

void WASMOON_GUEST_ABI gc_struct_set_v128_impl(int64_t ref, int32_t type_idx, int32_t field_idx,
                             int64_t value_ptr) {
    (void)type_idx;

    GcHeap *heap = resolve_heap(NULL);
    if (!heap || ref == 0) {
        if (ref == 0) trap_null_reference();
        else trap_unreachable_void();
        return;
    }

    int32_t gc_ref = decode_heap_ref(ref);
    gc_heap_struct_set_wide(heap, gc_ref, field_idx,
                            *(const GcSlot *)(uintptr_t)value_ptr);
}

void WASMOON_GUEST_ABI gc_array_get_v128_impl(int64_t ref, int32_t type_idx, int32_t idx,
                            int64_t out_ptr) {
    (void)type_idx;

    GcSlot *out = (GcSlot *)(uintptr_t)out_ptr;
    GcHeap *heap = resolve_heap(NULL);
    if (!heap || ref == 0) {
        if (ref == 0) trap_null_reference();
        else trap_unreachable_void();
        return;
    }

    int32_t gc_ref = decode_heap_ref(ref);
    int32_t len = gc_access_array_len(heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    *out = gc_heap_array_get_wide(heap, gc_ref, idx);
}

void WASMOON_GUEST_ABI gc_array_set_v128_impl(int64_t ref, int32_t type_idx, int32_t idx,
                            int64_t value_ptr) {
    (void)type_idx;

    GcHeap *heap = resolve_heap(NULL);
    if (!heap || ref == 0) {
        if (ref == 0) trap_null_reference();
        else trap_unreachable_void();
        return;
    }

    int32_t gc_ref = decode_heap_ref(ref);
    int32_t len = gc_access_array_len(heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_set_wide(heap, gc_ref, idx,
                           *(const GcSlot *)(uintptr_t)value_ptr);
}

void WASMOON_GUEST_ABI gc_array_fill_v128_impl(int64_t ref, int32_t offset, int64_t value_ptr,
                             int32_t count) {
    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        trap_unreachable_void();
        return;
    }
    if (ref == 0) {
        g_trap_code = WASMOON_TRAP_NULL_REFERENCE;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    int32_t gc_ref = decode_heap_ref(ref);
    int32_t len = gc_access_array_len(heap, gc_ref);
    if (offset < 0 || count < 0 || (int64_t)offset + count > len) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_fill_wide(heap, gc_ref, offset,
                            *(const GcSlot *)(uintptr_t)value_ptr, count);
}

int64_t WASMOON_GUEST_ABI gc_alloc_struct_wide_slow_impl(int64_t ctx_ptr, int32_t type_idx,
                                        int64_t slots_ptr, int32_t num_fields) {
    jit_context_t *ctx = resolve_ctx((jit_context_t *)(uintptr_t)ctx_ptr);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    const GcSlot *slots = (const GcSlot *)(uintptr_t)slots_ptr;
    gc_allocation_request_t request = {
        .ctx = ctx, .heap = heap, .layout = GC_ALLOC_STRUCT_SLOTS,
        .type_idx = type_idx, .values = slots, .count = num_fields,
        .init = {0, 0}
    };
    int32_t gc_ref = gc_allocate(&request);
    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }

    if (ctx) {
        ctx_set_gc_heap(ctx, heap);
        ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    }
    return ((int64_t)gc_ref) << 1;
}

int64_t WASMOON_GUEST_ABI gc_alloc_array_wide_slow_impl(int64_t ctx_ptr, int32_t type_idx,
                                       int32_t len, int64_t init_ptr) {
    if (array_length_exceeds_layout(len)) return trap_allocation_too_large();
    jit_context_t *ctx = resolve_ctx((jit_context_t *)(uintptr_t)ctx_ptr);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    GcSlot init = *(const GcSlot *)(uintptr_t)init_ptr;
    gc_allocation_request_t request = {
        .ctx = ctx, .heap = heap, .layout = GC_ALLOC_ARRAY_SLOT,
        .type_idx = type_idx, .values = NULL, .count = len,
        .init = init
    };
    int32_t gc_ref = gc_allocate(&request);
    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }

    if (ctx) {
        ctx_set_gc_heap(ctx, heap);
        ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    }
    return ((int64_t)gc_ref) << 1;
}

int64_t WASMOON_GUEST_ABI gc_alloc_array_from_slots_slow_impl(int64_t ctx_ptr, int32_t type_idx,
                                             int64_t slots_ptr, int32_t len) {
    if (array_length_exceeds_layout(len)) return trap_allocation_too_large();
    jit_context_t *ctx = resolve_ctx((jit_context_t *)(uintptr_t)ctx_ptr);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    const GcSlot *slots = (const GcSlot *)(uintptr_t)slots_ptr;
    gc_allocation_request_t request = {
        .ctx = ctx, .heap = heap, .layout = GC_ALLOC_ARRAY_SLOTS,
        .type_idx = type_idx, .values = slots, .count = len,
        .init = {0, 0}
    };
    int32_t gc_ref = gc_allocate(&request);
    if (gc_ref < 0) {
        return trap_gc_allocation_i64(gc_ref);
    }

    if (ctx) {
        ctx_set_gc_heap(ctx, heap);
        ctx_set_gc_heap_ptr(ctx, heap->data + heap->size);
        ctx_set_gc_heap_limit(ctx, gc_heap_allocation_limit(heap));
    }
    return ((int64_t)gc_ref) << 1;
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(gc_alloc_array_from_slots_slow_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_alloc_array_from_values_slow);
WASMOON_DEFINE_GUEST_TARGET(gc_alloc_array_slow);
WASMOON_DEFINE_GUEST_TARGET(gc_alloc_array_wide_slow_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_alloc_struct_slow);
WASMOON_DEFINE_GUEST_TARGET(gc_alloc_struct_wide_slow_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_copy_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_fill_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_fill_v128_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_get_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_get_v128_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_len_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_new_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_set_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_set_v128_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_register_array_inline);
WASMOON_DEFINE_GUEST_TARGET(gc_register_struct_inline);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_get_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_get_v128_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_new_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_set_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_set_v128_impl);
#endif

int64_t WASMOON_GUEST_ABI gc_struct_get_heap_impl(GcHeap *heap, int64_t ref, int32_t field_idx) {

    if (!heap) {
        return trap_unreachable_i64();
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        return trap_null_reference();
    }

    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = decode_heap_ref(ref);
    return gc_access_struct_get(heap, gc_ref, field_idx).lo;
}

void WASMOON_GUEST_ABI gc_struct_set_heap_impl(GcHeap *heap, int64_t ref, int32_t field_idx, int64_t value) {

    if (!heap) {
        trap_unreachable_void();
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        trap_null_reference();
        return;
    }

    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = decode_heap_ref(ref);
    gc_access_struct_set(heap, gc_ref, field_idx, (GcSlot){value, 0});
}

_Static_assert(GC_ARRAY_DATA_OFFSET == 16, "numeric array view ABI");

// Nontrapping numeric-array projection, including null heaps/references.
// The compiler may prepare it before an array operation actually executes.
// Actual operations keep their checked fallback and null/bounds traps.
// The compiler must not retain this pointer
// across allocation, polling, calls or reentry. Every CFG path (including
// loop backedges) must belong to a compiler-verified no-safepoint region.
// width=0 returns an opaque width-tagged view; refinements strip its tag.
// Positive-width compatibility calls return the actual payload: i32 length
// at offset zero and elements at offset 16. A zero result selects the existing
// checked accessor (including verification).
void* WASMOON_GUEST_ABI gc_array_data_heap_impl(GcHeap *heap, int64_t ref, int32_t width) {
    if (!heap || !ref || ref < 0 || ref > (int64_t)INT32_MAX * 2 || (ref & 1)) return NULL;
    if (gc_verify_env_cached != 0) return NULL;
    GcHeader *header = gc_access_object_header(heap, decode_heap_ref(ref));
    if (!header || header->kind != GC_KIND_ARRAY) return NULL;
    GcTypeLayout *layout = gc_object_layout(heap, header);
    int compact = layout && layout->count == 1 && layout->fields[0].offset == 0 &&
        layout->fields[0].width == layout->size && !layout->fields[0].reference;
    if (width == 0) {
        uintptr_t code = !compact ? 0 : layout->size == 1 ? 1 : layout->size == 2 ? 2 :
            layout->size == 4 ? 3 : layout->size == 8 ? 4 : 0;
        // Opaque metadata view: length remains available even for legacy or
        // reference arrays. Element refinement checks the exact width tag.
        return (void *)((uintptr_t)(header + 1) | code);
    }
    if (!compact || layout->size != width) return NULL;
    return header + 1;
}

// Checked once per object/type and heap epoch. Subsequent field projections
// are nontrapping metadata reads from this admitted, live struct payload.
void* WASMOON_GUEST_ABI gc_struct_data_impl(jit_context_t *ctx, int64_t ref, int32_t type_idx,
    uint64_t shape, int32_t fields) {
    if (!ref) { trap_null_reference(); return NULL; }
    ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap || ref < 0 || ref > (int64_t)INT32_MAX * 2 || (ref & 1) || fields < 0 || fields > 16) {
        trap_unreachable_i64(); return NULL;
    }
    int32_t target = ctx && ctx_runtime(ctx)->callable_local_types && type_idx >= 0 &&
        type_idx < ctx_runtime(ctx)->callable_local_type_count
        ? ctx_runtime(ctx)->callable_local_types[type_idx] : -1;
    GcStructViewCache *cached = &heap->struct_view;
    if (gc_verify_env_cached == 0 && target >= 0 &&
        cached->reference == ref && cached->identity == target &&
        cached->shape == shape && cached->fields == fields) return cached->payload;
    GcHeader *header = gc_access_object_header(heap, decode_heap_ref(ref));
    if (!header || header->kind != GC_KIND_STRUCT || (uint32_t)header->reserved < (uint32_t)fields) {
        trap_unreachable_i64(); return NULL;
    }
    int32_t identity = (int32_t)(header->reserved >> 32) - 1;
    int exact = identity >= 0 && identity == target;
    if (!exact && !gc_ref_test_impl(ctx, ref, type_idx, 0)) { trap_unreachable_i64(); return NULL; }
    GcTypeLayout *layout = gc_object_layout(heap, header);
    uint64_t mask = fields == 16 ? UINT64_MAX : (UINT64_C(1) << (fields * 4)) - 1;
    if (layout && (layout->kind != GC_KIND_STRUCT || layout->count < fields || (layout->prefix_shape & mask) != shape)) {
        trap_unreachable_i64(); return NULL;
    }
    // An opaque admitted view, never a dereferenceable guest address. Low bits
    // select the explicit legacy slot adapter and verification write fallback.
    uintptr_t flags = layout ? 0 : 1;
    if (!layout || gc_verify_env_cached != 0) flags |= 2;
    void *view = (void *)((uintptr_t)(header + 1) | flags);
    if (exact && layout && gc_verify_env_cached == 0) {
        *cached = (GcStructViewCache){ref, identity, fields, shape, view};
    }
    return view;
}

int64_t WASMOON_GUEST_ABI gc_array_get_heap_impl(GcHeap *heap, int64_t ref, int32_t idx) {
    if (!heap) { return trap_unreachable_i64(); }
    if (!ref) { return trap_null_reference(); }
    int32_t gc_ref = decode_heap_ref(ref);
    GcHeader *header = gc_access_object_header(heap, gc_ref);
    uint8_t *data = header ? (uint8_t *)(header + 1) : NULL;
    int32_t length = data ? *(int32_t *)data : 0;
    if (idx < 0 || idx >= length) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 0;
    }
    GcTypeLayout *layout = gc_object_layout(heap, header);
    GcFieldLayout access = layout ? layout->fields[0] : (GcFieldLayout){0, 16, 1};
    uint8_t *element = data + GC_ARRAY_DATA_OFFSET +
        (size_t)idx * (layout ? layout->size : 16);
    return gc_access_layout_read(element, &access).lo;
}

void WASMOON_GUEST_ABI gc_array_set_heap_impl(GcHeap *heap, int64_t ref, int32_t idx, int64_t value) {
    if (!heap) { trap_unreachable_void(); return; }
    if (!ref) { trap_null_reference(); return; }
    int32_t gc_ref = decode_heap_ref(ref);
    GcHeader *header = gc_access_object_header(heap, gc_ref);
    uint8_t *data = header ? (uint8_t *)(header + 1) : NULL;
    int32_t length = data ? *(int32_t *)data : 0;
    if (idx < 0 || idx >= length) {
        g_trap_code = WASMOON_TRAP_ARRAY_BOUNDS;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return;
    }
    GcTypeLayout *layout = gc_object_layout(heap, header);
    GcFieldLayout access = layout ? layout->fields[0] : (GcFieldLayout){0, 16, 1};
    uint8_t *element = data + GC_ARRAY_DATA_OFFSET +
        (size_t)idx * (layout ? layout->size : 16);
    GcSlot slot = {value, 0};
    if (access.reference) gc_heap_write_barrier(heap, gc_ref, value);
    gc_access_layout_write(element, &access, slot);
    gc_access_verify(heap, "array_set");
}

int32_t WASMOON_GUEST_ABI gc_array_len_heap_impl(GcHeap *heap, int64_t ref) {
    if (!heap) {
        return trap_unreachable_i32();
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        trap_null_reference();
        return 0;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);
    return gc_access_array_len(heap, gc_ref);
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(gc_reserve_struct_fast_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_try_array_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_try_array_wide_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_data_heap_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_data_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_get_heap_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_len_heap_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_array_set_heap_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_get_heap_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_struct_set_heap_impl);
#endif
