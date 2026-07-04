// Copyright 2025
// GC operations for JIT runtime
// Implements struct.new/get/set, array.new/get/set/len/fill/copy

#include "jit_internal.h"
#include "gc_allocator.h"

// ============ Value Decoding Helpers ============

static inline int32_t decode_heap_ref(int64_t val) {
    return (int32_t)(val >> 1);
}

static inline jit_context_t *resolve_ctx(jit_context_t *ctx) {
    if (ctx) return ctx;
    return get_current_jit_context();
}

static inline GcHeap *resolve_heap(jit_context_t *ctx) {
    jit_context_t *actual = resolve_ctx(ctx);
    if (!actual || !actual->gc_heap) return NULL;
    return (GcHeap *)actual->gc_heap;
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

static uint32_t gc_read_u32_le(const uint8_t *ptr) {
    return ((uint32_t)ptr[0]) |
           ((uint32_t)ptr[1] << 8) |
           ((uint32_t)ptr[2] << 16) |
           ((uint32_t)ptr[3] << 24);
}

static const wasmoon_gc_safepoint_table_t *gc_func_safepoint_table_for_current(
    jit_context_t *ctx
) {
    if (!ctx || !ctx->gc_func_safepoint_tables) {
        return NULL;
    }
    int32_t func_idx = ctx->debug_current_func_idx;
    if (func_idx < 0 || func_idx >= ctx->gc_func_safepoint_table_count) {
        return NULL;
    }
    const wasmoon_gc_safepoint_table_t *table = &ctx->gc_func_safepoint_tables[func_idx];
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
    table = ctx->gc_safepoint_table;
    if (ctx->gc_frame_chain_head && ctx->gc_frame_chain_head->table) {
        table = ctx->gc_frame_chain_head->table;
    }
    return table;
}

static int gc_alloc_debug_enabled(void);

static int32_t gc_clamp_root_count(int32_t root_count, int32_t fallback) {
    if (root_count <= 0) {
        return 0;
    }
    if (fallback <= 0) {
        return 0;
    }
    if (root_count > fallback) {
        return fallback;
    }
    return root_count;
}

static int gc_requires_precise_roots(int32_t safepoint_id) {
    return safepoint_id >= 0;
}

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

static int32_t gc_select_alloc_roots(
    const char *op,
    jit_context_t *ctx,
    int32_t safepoint_id,
    const int64_t *roots,
    int32_t fallback_root_count,
    const int64_t **selected_roots_out,
    int64_t **selected_roots_owned
) {
    if (selected_roots_out) {
        *selected_roots_out = roots;
    }
    if (selected_roots_owned) {
        *selected_roots_owned = NULL;
    }
    if (!roots || fallback_root_count <= 0) {
        return 0;
    }

    int32_t root_count = gc_clamp_root_count(fallback_root_count, fallback_root_count);
    if (!gc_requires_precise_roots(safepoint_id)) {
        return root_count;
    }
    if (!ctx) {
        gc_log_precise_root_failure(op, safepoint_id, "missing jit context");
        return -1;
    }
    const wasmoon_gc_safepoint_table_t *table = gc_active_safepoint_table(ctx);
    if (!table || !table->stackmap_blob || table->stackmap_blob_size < 8) {
        gc_log_precise_root_failure(op, safepoint_id, "missing safepoint table");
        return -1;
    }
    const uint8_t *blob = table->stackmap_blob;
    uint32_t version = gc_read_u32_le(blob);
    if (version != 2u) {
        gc_log_precise_root_failure(op, safepoint_id, "stackmap v2 required");
        return -1;
    }
    uint32_t count = gc_read_u32_le(blob + 4);
    if ((uint32_t)safepoint_id >= count) {
        gc_log_precise_root_failure(op, safepoint_id, "safepoint id out of range");
        return -1;
    }

    size_t offset = 8u;
    for (uint32_t i = 0; i < count; i++) {
        if (offset + 8u > table->stackmap_blob_size) {
            gc_log_precise_root_failure(op, safepoint_id, "truncated stackmap header");
            return -1;
        }
        uint32_t encoded_root_count = gc_read_u32_le(blob + offset);
        uint32_t index_count = gc_read_u32_le(blob + offset + 4u);
        offset += 8u;
        size_t index_bytes = (size_t)index_count * 4u;
        if (offset + index_bytes > table->stackmap_blob_size) {
            gc_log_precise_root_failure(op, safepoint_id, "truncated stackmap index list");
            return -1;
        }
        if (i != (uint32_t)safepoint_id) {
            offset += index_bytes;
            continue;
        }

        int32_t encoded_clamped = gc_clamp_root_count((int32_t)encoded_root_count, fallback_root_count);
        if (encoded_clamped > 0) {
            root_count = encoded_clamped;
        } else {
            return 0;
        }
        if (index_count == 0u) {
            gc_log_precise_root_failure(op, safepoint_id, "missing root indices");
            return -1;
        }
        if (index_count < (uint32_t)root_count) {
            gc_log_precise_root_failure(op, safepoint_id, "root index count too small");
            return -1;
        }
        int64_t *selected = (int64_t *)malloc((size_t)root_count * sizeof(int64_t));
        if (!selected) {
            gc_log_precise_root_failure(op, safepoint_id, "out of memory while selecting roots");
            return -1;
        }
        int invalid_index = 0;
        for (int32_t j = 0; j < root_count; j++) {
            uint32_t root_idx = gc_read_u32_le(blob + offset + ((size_t)j * 4u));
            if (root_idx < (uint32_t)fallback_root_count) {
                selected[j] = roots[root_idx];
            } else {
                invalid_index = 1;
                break;
            }
        }
        if (invalid_index) {
            free(selected);
            gc_log_precise_root_failure(op, safepoint_id, "root index out of bounds");
            return -1;
        }
        if (selected_roots_out) {
            *selected_roots_out = selected;
        }
        if (selected_roots_owned) {
            *selected_roots_owned = selected;
        }
        return root_count;
    }
    gc_log_precise_root_failure(op, safepoint_id, "safepoint entry not found");
    return -1;
}

// ============ Struct Operations ============

int64_t gc_struct_new_impl(int32_t type_idx, int64_t *fields, int32_t num_fields) {
    jit_context_t *ctx = get_current_jit_context();
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
        ctx->gc_type_cache &&
        type_idx >= 0 &&
        type_idx < ctx->gc_num_types
    ) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields = ctx->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_STRUCT_NUM_FIELDS_OFF];
        if (actual_num_fields > 0) {
            // Allocate and zero-initialize default fields
            default_fields = (int64_t *)calloc((size_t)actual_num_fields, sizeof(int64_t));
            if (!default_fields) {
                return trap_out_of_memory_i64();
            }
            actual_fields = default_fields;
        }
    }

    gc_alloc_result_t alloc_result = {0};
    int32_t gc_ref = gc_alloc_struct_with_retry(
        ctx,
        heap,
        type_idx,
        actual_fields,
        actual_num_fields,
        actual_fields,
        actual_num_fields,
        &alloc_result
    );

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref == 0) {
        return trap_out_of_memory_i64();
    }
    gc_log_alloc_retry("struct.new", &alloc_result);

    if (ctx) {
        ctx->gc_heap = heap;
        ctx->gc_heap_ptr = heap->data + heap->size;
        ctx->gc_heap_limit = heap->data + heap->capacity;
    }

    // Encode for JIT: gc_ref << 1 (1-based gc_ref stays 1-based, just shifted)
    // This ensures gc_ref=1 becomes value=2, which doesn't conflict with null (0)
    return ((int64_t)gc_ref) << 1;
}

int64_t gc_struct_get_impl(int64_t ref, int32_t type_idx, int32_t field_idx) {
    (void)type_idx;  // type_idx not needed for access, only for type checking

    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        return trap_unreachable_i64();
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        return trap_unreachable_i64();
    }

    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = decode_heap_ref(ref);
    return gc_heap_struct_get(heap, gc_ref, field_idx);
}

void gc_struct_set_impl(int64_t ref, int32_t type_idx, int32_t field_idx, int64_t value) {
    (void)type_idx;

    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        trap_unreachable_void();
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        trap_unreachable_void();
        return;
    }

    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = decode_heap_ref(ref);
    gc_heap_struct_set(heap, gc_ref, field_idx, value);
}

// ============ Array Operations ============

int64_t gc_array_new_impl(int32_t type_idx, int32_t len, int64_t fill) {
    jit_context_t *ctx = resolve_ctx(NULL);
    GcHeap *heap = resolve_heap(ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    int64_t roots_buf[1] = { fill };
    gc_alloc_result_t alloc_result = {0};
    int32_t gc_ref = gc_alloc_array_with_retry(
        ctx,
        heap,
        type_idx,
        len,
        fill,
        roots_buf,
        1,
        &alloc_result
    );
    if (gc_ref == 0) {
        return trap_out_of_memory_i64();
    }
    gc_log_alloc_retry("array.new", &alloc_result);

    if (ctx) {
        ctx->gc_heap = heap;
        ctx->gc_heap_ptr = heap->data + heap->size;
        ctx->gc_heap_limit = heap->data + heap->capacity;
    }

    // Encode: gc_ref << 1 (1-based gc_ref, ensures gc_ref=1 -> value=2)
    return ((int64_t)gc_ref) << 1;
}

int64_t gc_array_get_impl(int64_t ref, int32_t type_idx, int32_t idx) {
    (void)type_idx;

    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        return trap_unreachable_i64();
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        return trap_unreachable_i64();
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);

    // Check bounds
    int32_t len = gc_heap_array_len(heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    return gc_heap_array_get(heap, gc_ref, idx);
}

void gc_array_set_impl(int64_t ref, int32_t type_idx, int32_t idx, int64_t value) {
    (void)type_idx;

    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        trap_unreachable_void();
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        trap_unreachable_void();
        return;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);

    // Check bounds
    int32_t len = gc_heap_array_len(heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_set(heap, gc_ref, idx, value);
}

int32_t gc_array_len_impl(int64_t ref) {
    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        return trap_unreachable_i32();
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        return trap_unreachable_i32();
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);
    return gc_heap_array_len(heap, gc_ref);
}

void gc_array_fill_impl(int64_t ref, int32_t offset, int64_t value, int32_t count) {
    GcHeap *heap = resolve_heap(NULL);
    if (!heap) {
        trap_unreachable_void();
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = 2;  // Null reference
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);

    // Bounds check
    int32_t len = gc_heap_array_len(heap, gc_ref);
    if (offset < 0 || count < 0 || offset + count > len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_fill(heap, gc_ref, offset, value, count);
}

void gc_array_copy_impl(
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
        g_trap_code = 2;  // Null reference
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
        dst_offset + count > dst_len || src_offset + count > src_len
    ) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_copy(heap, dst_gc_ref, dst_offset, src_gc_ref, src_offset, count);
}

// ============ Inline Allocation Support ============

// Register a struct that was allocated inline by JIT code
// obj_ptr points to the object in the heap (header already initialized)
// Returns encoded gc_ref
int64_t gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size) {
    (void)total_size;
    jit_context_t *actual_ctx = resolve_ctx(ctx);
    if (!actual_ctx || !actual_ctx->gc_heap || !obj_ptr) {
        return trap_unreachable_i64();
    }

    GcHeap *heap = (GcHeap *)actual_ctx->gc_heap;

    // Ensure object table has capacity
    if (heap->object_count >= heap->object_capacity) {
        int32_t new_capacity = heap->object_capacity * 2;
        int32_t *new_table =
            (int32_t *)realloc(heap->object_table, (size_t)new_capacity * sizeof(int32_t));
        if (!new_table) {
            return trap_out_of_memory_i64();
        }
        heap->object_table = new_table;
        heap->object_capacity = new_capacity;
    }

    // Calculate offset and register object
    int32_t offset = (int32_t)(obj_ptr - heap->data);
    int32_t gc_ref = heap->object_count + 1;  // 1-based
    heap->object_table[heap->object_count] = offset;
    heap->object_count++;
    heap->total_allocations++;

    // Update heap size to match what JIT allocated
    heap->size = (size_t)(actual_ctx->gc_heap_ptr - heap->data);

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Slow path for struct allocation - called when inline check fails
// Triggers GC if needed, grows heap, and allocates
int64_t gc_alloc_struct_slow(
    jit_context_t *ctx,
    int32_t type_idx,
    int64_t *fields,
    int32_t num_fields,
    int32_t safepoint_id
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
        actual_ctx->gc_type_cache &&
        type_idx >= 0 &&
        type_idx < actual_ctx->gc_num_types
    ) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields =
            actual_ctx->gc_type_cache[type_idx * GC_TYPE_CACHE_STRIDE + GC_TYPE_STRUCT_NUM_FIELDS_OFF];
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
    int64_t *alloc_roots_owned = NULL;
    int32_t alloc_root_count = gc_select_alloc_roots(
        "alloc_struct_slow",
        actual_ctx,
        safepoint_id,
        fields,
        num_fields,
        &alloc_roots,
        &alloc_roots_owned
    );
    if (alloc_root_count < 0) {
        if (alloc_roots_owned) {
            free(alloc_roots_owned);
        }
        if (default_fields) {
            free(default_fields);
        }
        return trap_gc_precise_roots_i64();
    }

    gc_alloc_result_t alloc_result = {0};
    int32_t gc_ref = gc_alloc_struct_with_retry(
        actual_ctx,
        heap,
        type_idx,
        actual_fields,
        actual_num_fields,
        alloc_roots,
        alloc_root_count,
        &alloc_result
    );
    if (alloc_roots_owned) {
        free(alloc_roots_owned);
    }

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref == 0) {
        return trap_out_of_memory_i64();
    }
    gc_log_alloc_retry("alloc_struct_slow", &alloc_result);

    // Update VMContext heap pointers if ctx is available (heap may have grown)
    if (actual_ctx) {
        actual_ctx->gc_heap = heap;
        actual_ctx->gc_heap_ptr = heap->data + heap->size;
        actual_ctx->gc_heap_limit = heap->data + heap->capacity;
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Register an array that was allocated inline by JIT code
int64_t gc_register_array_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size) {
    // Same as struct registration - just register in object table
    return gc_register_struct_inline(ctx, obj_ptr, total_size);
}

// Slow path for array allocation
int64_t gc_alloc_array_slow(
    jit_context_t *ctx,
    int32_t type_idx,
    int32_t len,
    int64_t init_value,
    int32_t safepoint_id
) {
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
    int64_t *alloc_roots_owned = NULL;
    int32_t alloc_root_count = gc_select_alloc_roots(
        "alloc_array_slow",
        actual_ctx,
        safepoint_id,
        roots_buf,
        1,
        &alloc_roots,
        &alloc_roots_owned
    );
    if (alloc_root_count < 0) {
        if (alloc_roots_owned) {
            free(alloc_roots_owned);
        }
        if (gc_alloc_debug_enabled()) {
            fprintf(stderr, "[GC ALLOC] alloc_array_slow precise roots unavailable\n");
        }
        return trap_gc_precise_roots_i64();
    }

    gc_alloc_result_t alloc_result = {0};
    int32_t gc_ref = gc_alloc_array_with_retry(
        actual_ctx,
        heap,
        type_idx,
        len,
        init_value,
        alloc_roots,
        alloc_root_count,
        &alloc_result
    );
    if (alloc_roots_owned) {
        free(alloc_roots_owned);
    }
    if (gc_ref == 0) {
        if (gc_alloc_debug_enabled()) {
            fprintf(stderr, "[GC ALLOC] alloc_array_slow failed after retries\n");
        }
        return trap_out_of_memory_i64();
    }
    gc_log_alloc_retry("alloc_array_slow", &alloc_result);

    // Update VMContext heap pointers if ctx is available (heap may have grown)
    if (actual_ctx) {
        actual_ctx->gc_heap = heap;
        actual_ctx->gc_heap_ptr = heap->data + heap->size;
        actual_ctx->gc_heap_limit = heap->data + heap->capacity;
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Slow path for fixed array allocation from an explicit values buffer.
int64_t gc_alloc_array_from_values_slow(
    jit_context_t *ctx,
    int32_t type_idx,
    int64_t *values,
    int32_t len,
    int32_t safepoint_id
) {
    jit_context_t *actual_ctx = resolve_ctx(ctx);
    GcHeap *heap = resolve_heap(actual_ctx);
    if (!heap) {
        return trap_unreachable_i64();
    }

    const int64_t *alloc_roots = NULL;
    int64_t *alloc_roots_owned = NULL;
    int32_t alloc_root_count = gc_select_alloc_roots(
        "alloc_array_from_values_slow",
        actual_ctx,
        safepoint_id,
        values,
        len,
        &alloc_roots,
        &alloc_roots_owned
    );
    if (alloc_root_count < 0) {
        if (alloc_roots_owned) {
            free(alloc_roots_owned);
        }
        return trap_gc_precise_roots_i64();
    }

    gc_alloc_result_t alloc_result = {0};
    int32_t gc_ref = gc_alloc_array_from_values_with_retry(
        actual_ctx,
        heap,
        type_idx,
        values,
        len,
        alloc_roots,
        alloc_root_count,
        &alloc_result
    );
    if (alloc_roots_owned) {
        free(alloc_roots_owned);
    }
    if (gc_ref == 0) {
        return trap_out_of_memory_i64();
    }
    gc_log_alloc_retry("alloc_array_from_values_slow", &alloc_result);

    if (actual_ctx) {
        actual_ctx->gc_heap = heap;
        actual_ctx->gc_heap_ptr = heap->data + heap->size;
        actual_ctx->gc_heap_limit = heap->data + heap->capacity;
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}
