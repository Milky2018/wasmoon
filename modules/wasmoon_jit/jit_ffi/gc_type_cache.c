// Copyright 2025
// GC type cache and type checking for JIT runtime
// Implements ref.test, ref.cast, and subtype checking

#include "jit_internal.h"

// ============ Value Encoding Helpers ============

static inline int is_null_value(int64_t val) {
    return val == 0;
}

static inline int is_externref_value(int64_t val) {
    return (val & EXTERNREF_TAG) != 0;  // Bit 62 set
}

static inline int is_funcref_ptr_value(int64_t val) {
    return (val & FUNCREF_TAG) != 0 && (val & EXTERNREF_TAG) == 0;  // Bit 61 set, bit 62 clear
}

static inline int is_funcref_value(int64_t val) {
    // Either negative (IR encoded) or tagged pointer (table entry)
    return val < 0 || is_funcref_ptr_value(val);
}

static inline int is_i31_value(int64_t val) {
    return val > 0 && (val & REF_TAGS_MASK) == 0 && (val & 1) == 1;  // Positive odd, no tags
}

static inline int is_heap_ref_value(int64_t val) {
    return val > 0 && (val & REF_TAGS_MASK) == 0 && (val & 1) == 0;  // Positive even (>= 2), no tags
}

static inline jit_context_t *current_ctx(void) {
    return get_current_jit_context();
}

static int is_concrete_subtype(
    jit_context_t *ctx,
    int32_t actual_type,
    int32_t expected_type
) {
    if (!ctx || !ctx->gc_type_cache) return 0;
    if (actual_type < 0 || actual_type >= ctx->gc_num_types) return 0;
    if (expected_type < 0 || expected_type >= ctx->gc_num_types) return 0;

    int32_t target_canonical = expected_type;
    if (ctx->gc_canonical_indices && expected_type < ctx->gc_num_canonical) {
        target_canonical = ctx->gc_canonical_indices[expected_type];
    }

    int32_t current_type = actual_type;
    while (current_type >= 0 && current_type < ctx->gc_num_types) {
        int32_t current_canonical = current_type;
        if (ctx->gc_canonical_indices && current_type < ctx->gc_num_canonical) {
            current_canonical = ctx->gc_canonical_indices[current_type];
        }
        if (current_canonical == target_canonical) {
            return 1;
        }
        int32_t super_idx =
            ctx->gc_type_cache[current_type * GC_TYPE_CACHE_STRIDE + GC_TYPE_SUPER_IDX_OFF];
        if (super_idx < 0 || super_idx == current_type) {
            break;
        }
        current_type = super_idx;
    }
    return 0;
}

static int is_subtype_cached_ctx(jit_context_t *ctx, int type1, int type2) {
    if (type1 == type2) return 1;
    if (!ctx || !ctx->gc_type_cache) return 0;
    if (type1 < 0 || type1 >= ctx->gc_num_types) return 0;
    if (type2 < 0 || type2 >= ctx->gc_num_types) return 0;

    // Check canonical indices first (if available)
    if (ctx->gc_canonical_indices && ctx->gc_num_canonical > 0) {
        if (type1 < ctx->gc_num_canonical && type2 < ctx->gc_num_canonical) {
            if (ctx->gc_canonical_indices[type1] == ctx->gc_canonical_indices[type2]) {
                return 1;
            }
        }
    }

    // Walk the supertype chain
    int current = type1;
    while (current >= 0 && current < ctx->gc_num_types) {
        if (current == type2) return 1;
        int super_idx = ctx->gc_type_cache[current * GC_TYPE_CACHE_STRIDE + GC_TYPE_SUPER_IDX_OFF];
        if (super_idx < 0) break;  // No more supertypes
        if (super_idx == current) break;  // Avoid infinite loop
        current = super_idx;
    }
    return 0;
}

// ============ Subtype Checking ============

int is_subtype_cached(int type1, int type2) {
    return is_subtype_cached_ctx(current_ctx(), type1, type2);
}

// ============ ref.test Implementation ============

int32_t gc_ref_test_impl(int64_t value, int32_t type_idx, int32_t nullable) {
    jit_context_t *ctx = current_ctx();

    // Handle null
    if (is_null_value(value)) {
        return nullable ? 1 : 0;
    }

    // Handle externref values (bit 62 set) - MUST check before other types
    if (is_externref_value(value)) {
        switch (type_idx) {
            case ABSTRACT_TYPE_ANY:
            case ABSTRACT_TYPE_EXTERN:
                return 1;
            default:
                return 0;
        }
    }

    // Handle funcref values (negative or tagged pointer)
    if (is_funcref_value(value)) {
        switch (type_idx) {
            case ABSTRACT_TYPE_FUNC:
                return 1;
            case ABSTRACT_TYPE_NOFUNC:
            case ABSTRACT_TYPE_NONE:
            case ABSTRACT_TYPE_ANY:
            case ABSTRACT_TYPE_EQ:
            case ABSTRACT_TYPE_I31:
            case ABSTRACT_TYPE_STRUCT:
            case ABSTRACT_TYPE_ARRAY:
            case ABSTRACT_TYPE_EXTERN:
            case ABSTRACT_TYPE_NOEXTERN:
                return 0;
            default: {
                // For concrete type indices, check if the function's type is a subtype
                if (!ctx || !ctx->gc_func_type_indices || !ctx->gc_type_cache) {
                    return 0;
                }

                int32_t func_idx = -1;

                if (value < 0) {
                    // IR-encoded funcref: value = -(func_idx + 1)
                    func_idx = (int32_t)(-(value + 1));
                } else if (is_funcref_ptr_value(value) && ctx->gc_func_table && ctx->gc_func_table_size > 0) {
                    // Tagged pointer funcref: search func_table for the ptr
                    void *raw_ptr = (void *)(uintptr_t)(value & ~FUNCREF_TAG);
                    for (int i = 0; i < ctx->gc_func_table_size; i++) {
                        if (ctx->gc_func_table[i] == raw_ptr) {
                            func_idx = i;
                            break;
                        }
                    }
                }

                if (func_idx >= 0 && func_idx < ctx->gc_num_funcs) {
                    int32_t func_type_idx = ctx->gc_func_type_indices[func_idx];
                    if (is_concrete_subtype(ctx, func_type_idx, type_idx)) {
                        return 1;
                    }
                }
                return 0;
            }
        }
    }

    // Handle i31 values (positive odd)
    if (is_i31_value(value)) {
        switch (type_idx) {
            case ABSTRACT_TYPE_ANY:
            case ABSTRACT_TYPE_EQ:
            case ABSTRACT_TYPE_I31:
            case ABSTRACT_TYPE_EXTERN:
                return 1;
            default:
                return 0;
        }
    }

    // Handle struct/array reference (positive even, heap reference)
    if (!is_heap_ref_value(value) || !ctx || !ctx->gc_heap) {
        return 0;
    }

    int32_t gc_ref = (int32_t)(value >> 1);
    if (gc_ref <= 0) {
        return 0;
    }

    GcHeap *heap = (GcHeap *)ctx->gc_heap;
    int32_t obj_kind = gc_heap_get_kind(heap, gc_ref);
    int32_t obj_type_idx = gc_heap_get_type_idx(heap, gc_ref);

    // Handle abstract types
    if (type_idx < 0) {
        switch (type_idx) {
            case ABSTRACT_TYPE_ANY:
                return 1;
            case ABSTRACT_TYPE_EQ:
                return (obj_kind == 1 || obj_kind == 2) ? 1 : 0;
            case ABSTRACT_TYPE_STRUCT:
                return (obj_kind == 1) ? 1 : 0;
            case ABSTRACT_TYPE_ARRAY:
                return (obj_kind == 2) ? 1 : 0;
            case ABSTRACT_TYPE_EXTERN:
                return (obj_kind == 1 || obj_kind == 2) ? 1 : 0;
            default:
                return 0;
        }
    }

    return is_concrete_subtype(ctx, obj_type_idx, type_idx);
}

// ============ ref.cast Implementation ============

int64_t gc_ref_cast_impl(int64_t value, int32_t type_idx, int32_t nullable) {
    int result = gc_ref_test_impl(value, type_idx, nullable);
    if (!result) {
        g_trap_code = 4;  // Type mismatch
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
    }
    return value;
}

// ============ Type Check for call_indirect ============

void gc_type_check_subtype_impl(int32_t actual_type, int32_t expected_type) {
    // Fast path: exact type match
    if (actual_type == expected_type) {
        return;
    }

    // Subtype check using type cache
    if (is_subtype_cached_ctx(current_ctx(), actual_type, expected_type)) {
        return;
    }

    // Types don't match - trap
    g_trap_code = 4;  // Indirect call type mismatch
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
}

// ============ Type Cache Management ============

void set_type_cache_internal(jit_context_t *ctx, int32_t *types_data, int num_types) {
    if (!ctx) return;
    if (ctx->gc_type_cache) {
        free(ctx->gc_type_cache);
        ctx->gc_type_cache = NULL;
    }

    ctx->gc_num_types = num_types;
    if (num_types > 0 && types_data) {
        size_t bytes = (size_t)num_types * GC_TYPE_CACHE_STRIDE * sizeof(int32_t);
        ctx->gc_type_cache = (int32_t *)malloc(bytes);
        if (ctx->gc_type_cache) {
            memcpy(ctx->gc_type_cache, types_data, bytes);
        }
    }
}

void set_canonical_indices_internal(jit_context_t *ctx, int32_t *canonical, int num_types) {
    if (!ctx) return;
    if (ctx->gc_canonical_indices) {
        free(ctx->gc_canonical_indices);
        ctx->gc_canonical_indices = NULL;
    }

    ctx->gc_num_canonical = num_types;
    if (num_types > 0 && canonical) {
        size_t bytes = (size_t)num_types * sizeof(int32_t);
        ctx->gc_canonical_indices = (int32_t *)malloc(bytes);
        if (ctx->gc_canonical_indices) {
            memcpy(ctx->gc_canonical_indices, canonical, bytes);
        }
    }
}

void set_func_type_indices_internal(jit_context_t *ctx, int32_t *indices, int num_funcs) {
    if (!ctx) return;
    if (ctx->gc_func_type_indices) {
        free(ctx->gc_func_type_indices);
        ctx->gc_func_type_indices = NULL;
    }

    ctx->gc_num_funcs = num_funcs;
    if (num_funcs > 0 && indices) {
        size_t bytes = (size_t)num_funcs * sizeof(int32_t);
        ctx->gc_func_type_indices = (int32_t *)malloc(bytes);
        if (ctx->gc_func_type_indices) {
            memcpy(ctx->gc_func_type_indices, indices, bytes);
        }
    }
}

void set_func_table_internal(jit_context_t *ctx, void **func_table_ptr, int num_funcs) {
    if (!ctx) return;
    ctx->gc_func_table = func_table_ptr;
    ctx->gc_func_table_size = num_funcs;
}

void clear_type_cache_internal(jit_context_t *ctx) {
    if (!ctx) return;

    if (ctx->gc_type_cache) {
        free(ctx->gc_type_cache);
        ctx->gc_type_cache = NULL;
    }
    ctx->gc_num_types = 0;

    if (ctx->gc_canonical_indices) {
        free(ctx->gc_canonical_indices);
        ctx->gc_canonical_indices = NULL;
    }
    ctx->gc_num_canonical = 0;

    if (ctx->gc_func_type_indices) {
        free(ctx->gc_func_type_indices);
        ctx->gc_func_type_indices = NULL;
    }
    ctx->gc_num_funcs = 0;

    ctx->gc_func_table = NULL;
    ctx->gc_func_table_size = 0;
}
