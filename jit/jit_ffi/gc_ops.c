// Copyright 2025
// GC operations for JIT runtime
// Implements struct.new/get/set, array.new/get/set/len/fill/copy

#include "jit_internal.h"

// ============ Global GC Heap Pointer ============

GcHeap *g_gc_heap = NULL;

// ============ Value Decoding Helpers ============

static inline int32_t decode_heap_ref(int64_t val) {
    return (int32_t)(val >> 1);
}

// ============ Struct Operations ============

int64_t gc_struct_new_impl(int32_t type_idx, int64_t *fields, int32_t num_fields) {
    if (!g_gc_heap) {
        g_trap_code = 3;  // Unreachable - GC heap not set
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Handle struct.new_default: num_fields == 0 means use default values
    int64_t *actual_fields = fields;
    int32_t actual_num_fields = num_fields;
    int64_t *default_fields = NULL;

    if (num_fields == 0 && g_gc_type_cache && type_idx >= 0 && type_idx < g_gc_num_types) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields = g_gc_type_cache[type_idx * 3 + 2];
        if (actual_num_fields > 0) {
            // Allocate and zero-initialize default fields
            default_fields = (int64_t *)calloc(actual_num_fields, sizeof(int64_t));
            if (!default_fields) {
                g_trap_code = 3;  // Allocation failed
                if (g_trap_active) {
                    siglongjmp(g_trap_jmp_buf, 1);
                }
                return 0;
            }
            actual_fields = default_fields;
        }
    }

    // Allocate struct and return encoded reference
    // gc_heap uses 1-based gc_ref, JIT uses (gc_ref << 1) encoding
    int32_t gc_ref = gc_heap_alloc_struct(g_gc_heap, type_idx, actual_fields, actual_num_fields);

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref == 0) {
        g_trap_code = 3;  // Allocation failed
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Encode for JIT: gc_ref << 1 (1-based gc_ref stays 1-based, just shifted)
    // This ensures gc_ref=1 becomes value=2, which doesn't conflict with null (0)
    int64_t encoded = ((int64_t)gc_ref) << 1;
    return encoded;
}

int64_t gc_struct_get_impl(int64_t ref, int32_t type_idx, int32_t field_idx) {
    (void)type_idx;  // type_idx not needed for access, only for type checking

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = 3;  // null structure reference
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = decode_heap_ref(ref);
    int64_t result = gc_heap_struct_get(g_gc_heap, gc_ref, field_idx);
    return result;
}

void gc_struct_set_impl(int64_t ref, int32_t type_idx, int32_t field_idx, int64_t value) {
    (void)type_idx;

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = 3;  // null structure reference
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = decode_heap_ref(ref);
    gc_heap_struct_set(g_gc_heap, gc_ref, field_idx, value);
}

// ============ Array Operations ============

int64_t gc_array_new_impl(int32_t type_idx, int32_t len, int64_t fill) {
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    int32_t gc_ref = gc_heap_alloc_array(g_gc_heap, type_idx, len, fill);
    if (gc_ref == 0) {
        g_trap_code = 3;  // Allocation failed
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Encode: gc_ref << 1 (1-based gc_ref, ensures gc_ref=1 -> value=2)
    int64_t encoded = ((int64_t)gc_ref) << 1;
    return encoded;
}

int64_t gc_array_get_impl(int64_t ref, int32_t type_idx, int32_t idx) {
    (void)type_idx;

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = 3;  // null array reference
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);

    // Check bounds
    int32_t len = gc_heap_array_len(g_gc_heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    return gc_heap_array_get(g_gc_heap, gc_ref, idx);
}

void gc_array_set_impl(int64_t ref, int32_t type_idx, int32_t idx, int64_t value) {
    (void)type_idx;

    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = 3;  // null array reference
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);

    // Check bounds
    int32_t len = gc_heap_array_len(g_gc_heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_set(g_gc_heap, gc_ref, idx, value);
}

int32_t gc_array_len_impl(int64_t ref) {
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Check for null reference (encoded as 0)
    if (ref == 0) {
        g_trap_code = 3;  // null array reference
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = decode_heap_ref(ref);
    return gc_heap_array_len(g_gc_heap, gc_ref);
}

void gc_array_fill_impl(int64_t ref, int32_t offset, int64_t value, int32_t count) {
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
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
    int32_t len = gc_heap_array_len(g_gc_heap, gc_ref);
    if (offset < 0 || count < 0 || offset + count > len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_fill(g_gc_heap, gc_ref, offset, value, count);
}

void gc_array_copy_impl(int64_t dst_ref, int32_t dst_offset,
                        int64_t src_ref, int32_t src_offset, int32_t count) {
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
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
    int32_t dst_len = gc_heap_array_len(g_gc_heap, dst_gc_ref);
    int32_t src_len = gc_heap_array_len(g_gc_heap, src_gc_ref);
    if (dst_offset < 0 || src_offset < 0 || count < 0 ||
        dst_offset + count > dst_len || src_offset + count > src_len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    gc_heap_array_copy(g_gc_heap, dst_gc_ref, dst_offset, src_gc_ref, src_offset, count);
}

// ============ Inline Allocation Support ============

// Register a struct that was allocated inline by JIT code
// obj_ptr points to the object in the heap (header already initialized)
// Returns encoded gc_ref
int64_t gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size) {
    if (!ctx || !ctx->gc_heap || !obj_ptr) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    GcHeap *heap = (GcHeap *)ctx->gc_heap;

    // Ensure object table has capacity
    if (heap->object_count >= heap->object_capacity) {
        int32_t new_capacity = heap->object_capacity * 2;
        int32_t *new_table = (int32_t *)realloc(heap->object_table,
                                                  new_capacity * sizeof(int32_t));
        if (!new_table) {
            g_trap_code = 3;
            if (g_trap_active) {
                siglongjmp(g_trap_jmp_buf, 1);
            }
            return 0;
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
    heap->size = (size_t)(ctx->gc_heap_ptr - heap->data);

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}

// Slow path for struct allocation - called when inline check fails
// Triggers GC if needed, grows heap, and allocates
int64_t gc_alloc_struct_slow(jit_context_t *ctx, int32_t type_idx,
                              int64_t *fields, int32_t num_fields) {
    // Try ctx->gc_heap first, fall back to global g_gc_heap
    GcHeap *heap = ctx ? (GcHeap *)ctx->gc_heap : NULL;
    if (!heap) {
        heap = g_gc_heap;
    }
    if (!heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Handle struct.new_default: num_fields == 0 means use default values
    int64_t *actual_fields = fields;
    int32_t actual_num_fields = num_fields;
    int64_t *default_fields = NULL;

    if (num_fields == 0 && g_gc_type_cache && type_idx >= 0 && type_idx < g_gc_num_types) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields = g_gc_type_cache[type_idx * 3 + 2];
        if (actual_num_fields > 0) {
            // Allocate and zero-initialize default fields
            default_fields = (int64_t *)calloc(actual_num_fields, sizeof(int64_t));
            if (!default_fields) {
                g_trap_code = 3;  // Allocation failed
                if (g_trap_active) {
                    siglongjmp(g_trap_jmp_buf, 1);
                }
                return 0;
            }
            actual_fields = default_fields;
        }
    }

    // Try to allocate (this will grow heap if needed)
    int32_t gc_ref = gc_heap_alloc_struct(heap, type_idx, actual_fields, actual_num_fields);

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref == 0) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Update VMContext heap pointers if ctx is available (heap may have grown)
    // Also set ctx->gc_heap if we fell back to g_gc_heap, to keep VMContext in sync
    if (ctx) {
        ctx->gc_heap = heap;
        ctx->gc_heap_ptr = heap->data + heap->size;
        ctx->gc_heap_limit = heap->data + heap->capacity;
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
int64_t gc_alloc_array_slow(jit_context_t *ctx, int32_t type_idx,
                             int32_t len, int64_t init_value) {
    // Try ctx->gc_heap first, fall back to global g_gc_heap
    GcHeap *heap = ctx ? (GcHeap *)ctx->gc_heap : NULL;
    if (!heap) {
        heap = g_gc_heap;
    }
    if (!heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Try to allocate (this will grow heap if needed)
    int32_t gc_ref = gc_heap_alloc_array(heap, type_idx, len, init_value);
    if (gc_ref == 0) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Update VMContext heap pointers if ctx is available (heap may have grown)
    // Also set ctx->gc_heap if we fell back to g_gc_heap, to keep VMContext in sync
    if (ctx) {
        ctx->gc_heap = heap;
        ctx->gc_heap_ptr = heap->data + heap->size;
        ctx->gc_heap_limit = heap->data + heap->capacity;
    }

    // Encode: gc_ref << 1
    return ((int64_t)gc_ref) << 1;
}
