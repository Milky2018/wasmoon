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
    if (!ctx || !ctx_runtime(ctx)->gc_type_cache) return 0;
    if (actual_type < 0 || actual_type >= ctx_runtime(ctx)->gc_num_types) return 0;
    if (expected_type < 0 || expected_type >= ctx_runtime(ctx)->gc_num_types) return 0;

    int32_t target_canonical = expected_type;
    if (ctx_runtime(ctx)->gc_canonical_indices && expected_type < ctx_runtime(ctx)->gc_num_canonical) {
        target_canonical = ctx_runtime(ctx)->gc_canonical_indices[expected_type];
    }

    int32_t current_type = actual_type;
    while (current_type >= 0 && current_type < ctx_runtime(ctx)->gc_num_types) {
        int32_t current_canonical = current_type;
        if (ctx_runtime(ctx)->gc_canonical_indices && current_type < ctx_runtime(ctx)->gc_num_canonical) {
            current_canonical = ctx_runtime(ctx)->gc_canonical_indices[current_type];
        }
        if (current_canonical == target_canonical) {
            return 1;
        }
        int32_t super_idx =
            ctx_runtime(ctx)->gc_type_cache[current_type * GC_TYPE_CACHE_STRIDE + GC_TYPE_SUPER_IDX_OFF];
        if (super_idx < 0 || super_idx == current_type) {
            break;
        }
        current_type = super_idx;
    }
    return 0;
}

static int is_subtype_cached_ctx(jit_context_t *ctx, int type1, int type2) {
    if (type1 == type2) return 1;
    if (!ctx || !ctx_runtime(ctx)->gc_type_cache) return 0;
    if (type1 < 0 || type1 >= ctx_runtime(ctx)->gc_num_types) return 0;
    if (type2 < 0 || type2 >= ctx_runtime(ctx)->gc_num_types) return 0;

    // Check canonical indices first (if available)
    if (ctx_runtime(ctx)->gc_canonical_indices && ctx_runtime(ctx)->gc_num_canonical > 0) {
        if (type1 < ctx_runtime(ctx)->gc_num_canonical && type2 < ctx_runtime(ctx)->gc_num_canonical) {
            if (ctx_runtime(ctx)->gc_canonical_indices[type1] == ctx_runtime(ctx)->gc_canonical_indices[type2]) {
                return 1;
            }
        }
    }

    // Walk the supertype chain
    int current = type1;
    while (current >= 0 && current < ctx_runtime(ctx)->gc_num_types) {
        if (current == type2) return 1;
        int super_idx = ctx_runtime(ctx)->gc_type_cache[current * GC_TYPE_CACHE_STRIDE + GC_TYPE_SUPER_IDX_OFF];
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

static int callable_subtype(jit_context_t *ctx, int32_t actual, int32_t local_expected);

// ============ ref.test Implementation ============

int32_t WASMOON_GUEST_ABI gc_ref_test_impl(jit_context_t *ctx, int64_t value, int32_t type_idx, int32_t nullable) {

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
                if (ctx && ctx_runtime(ctx)->callable_local_types) {
                    return callable_subtype(ctx, callable_type_for_value(ctx, value), type_idx);
                }
                // For concrete type indices, check if the function's type is a subtype
                if (!ctx || !ctx_runtime(ctx)->gc_func_type_indices || !ctx_runtime(ctx)->gc_type_cache) {
                    return 0;
                }

                int32_t func_idx = -1;

                if (value < 0) {
                    // IR-encoded funcref: value = -(func_idx + 1)
                    func_idx = (int32_t)(-(value + 1));
                } else if (is_funcref_ptr_value(value) && ctx_runtime(ctx)->gc_func_table && ctx_runtime(ctx)->gc_func_table_size > 0) {
                    // Tagged pointer funcref: search func_table for the ptr
                    void *raw_ptr = (void *)(uintptr_t)(value & ~FUNCREF_TAG);
                    for (int i = 0; i < ctx_runtime(ctx)->gc_func_table_size; i++) {
                        if (ctx_runtime(ctx)->gc_func_table[i] == (int64_t)(uintptr_t)raw_ptr) {
                            func_idx = i;
                            break;
                        }
                    }
                }

                if (func_idx >= 0 && func_idx < ctx_runtime(ctx)->gc_num_funcs) {
                    int32_t func_type_idx = ctx_runtime(ctx)->gc_func_type_indices[func_idx];
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

    if (gc_ref <= heap->object_count && heap->runtime_types[gc_ref - 1] >= 0) {
        return callable_subtype(ctx, heap->runtime_types[gc_ref - 1], type_idx);
    }
    return is_concrete_subtype(ctx, obj_type_idx, type_idx);
}

// ============ ref.cast Implementation ============

int64_t WASMOON_GUEST_ABI gc_ref_cast_impl(jit_context_t *ctx, int64_t value, int32_t type_idx, int32_t nullable) {
    int result = gc_ref_test_impl(ctx, value, type_idx, nullable);
    if (!result) {
        g_trap_code = WASMOON_TRAP_CAST_FAILURE;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
    }
    return value;
}

// ============ Type Check for call_indirect ============

static inline int callable_subtype_registered(
    const jit_runtime_state_t *state, int32_t actual, int32_t local_expected
) {
    if ((uint32_t)local_expected >= (uint32_t)state->callable_local_type_count) return 0;
    int32_t expected = state->callable_local_types[local_expected];
    const jit_callable_registry_t *registry = state->callable_registry;
    if (!registry) return 0;
    // Counts are nonnegative at publication. Snapshot the read-only view once;
    // unsigned bounds checks also reject negative type indices.
    uint32_t type_count = (uint32_t)registry->type_count;
    const int32_t *parents = registry->parents;
    while ((uint32_t)actual < type_count) {
        if (actual == expected) return 1;
        int32_t parent = parents[actual];
        if (parent == actual) return 0;
        actual = parent;
    }
    return 0;
}

static int callable_subtype(jit_context_t *ctx, int32_t actual, int32_t local_expected) {
    if (!ctx || !ctx_runtime(ctx)->callable_local_types)
        return is_subtype_cached_ctx(ctx, actual, local_expected);
    return callable_subtype_registered(ctx_runtime(ctx), actual, local_expected);
}

int32_t callable_type_for_value(jit_context_t *ctx, int64_t value) {
    if (!ctx || !value) return -1;
    uint64_t pointer;
    if (value < 0) {
        int64_t index = -(value + 1);
        if (index < 0 || index >= ctx->func_count) return -1;
        pointer = (uint64_t)(uintptr_t)ctx->func_table[index];
    } else {
        pointer = (uint64_t)value & ~FUNCREF_TAG;
    }
    const jit_callable_registry_t *registry = ctx_runtime(ctx)->callable_registry;
    if (!registry) return -1;
    int32_t low = 0, high = registry->entry_count;
    while (low < high) {
        int32_t middle = low + (high - low) / 2;
        if ((uint64_t)registry->addresses[middle] < pointer)
            low = middle + 1;
        else
            high = middle;
    }
    if (low < registry->entry_count && (uint64_t)registry->addresses[low] == pointer)
        return registry->identities[low];
    return -1;
}

void WASMOON_GUEST_ABI gc_type_check_subtype_impl(jit_context_t *ctx, int32_t actual_type, int32_t expected_type) {
    // Keep the Store-backed path leaf-like; the legacy cache fallback is larger.
    if (ctx && ctx_runtime(ctx)->callable_local_types) {
        if (callable_subtype_registered(ctx_runtime(ctx), actual_type, expected_type)) return;
    } else if (is_subtype_cached_ctx(ctx, actual_type, expected_type)) {
        return;
    }
    g_trap_code = 4;
    if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
}

// ============ Type Cache Management ============

// Legacy raw-pointer C setters copy into managed arrays. Raw input is never
// treated as a MoonBit object, and all retained cache slots use one RC contract.
static int32_t *copy_type_metadata(const int32_t *source, int32_t count) {
    if (!source || count <= 0) return NULL;
    int32_t *copy = moonbit_make_int32_array_raw(count);
    memcpy(copy, source, (size_t)count * sizeof(int32_t));
    return copy;
}

void set_type_cache_internal(jit_context_t *ctx, int32_t *types_data, int num_types) {
    if (!ctx || num_types < 0 || num_types > INT32_MAX / GC_TYPE_CACHE_STRIDE) return;
    int32_t *copy = copy_type_metadata(types_data, num_types * GC_TYPE_CACHE_STRIDE);
    if (ctx_runtime(ctx)->gc_type_cache) moonbit_decref(ctx_runtime(ctx)->gc_type_cache);
    ctx_runtime(ctx)->gc_type_cache = copy;
    ctx_runtime(ctx)->gc_num_types = num_types;
}

void set_canonical_indices_internal(jit_context_t *ctx, int32_t *canonical, int num_types) {
    if (!ctx || num_types < 0) return;
    int32_t *copy = copy_type_metadata(canonical, num_types);
    if (ctx_runtime(ctx)->gc_canonical_indices) moonbit_decref(ctx_runtime(ctx)->gc_canonical_indices);
    ctx_runtime(ctx)->gc_canonical_indices = copy;
    ctx_runtime(ctx)->gc_num_canonical = num_types;
}

void set_func_type_indices_internal(jit_context_t *ctx, int32_t *indices, int num_funcs) {
    if (!ctx || num_funcs < 0) return;
    int32_t *copy = copy_type_metadata(indices, num_funcs);
    if (ctx_runtime(ctx)->gc_func_type_indices) moonbit_decref(ctx_runtime(ctx)->gc_func_type_indices);
    ctx_runtime(ctx)->gc_func_type_indices = copy;
    ctx_runtime(ctx)->gc_num_funcs = num_funcs;
}

// The FFI conversion copies native pointers into typed MoonBit scalar storage.
MOONBIT_FFI_EXPORT int64_t *wasmoon_jit_snapshot_gc_function_addresses(
    int64_t table_address, int32_t count
) {
    if (count < 0) count = 0;
    void **table = (void **)(uintptr_t)table_address;
    int64_t *addresses = moonbit_make_int64_array(count, 0);
    if (table) {
        for (int32_t i = 0; i < count; ++i) addresses[i] = (int64_t)(uintptr_t)table[i];
    }
    return addresses;
}

void set_func_table_internal(jit_context_t *ctx, void **func_table_ptr, int num_funcs) {
    if (!ctx || num_funcs < 0) return;
    int64_t *copy = num_funcs ? wasmoon_jit_snapshot_gc_function_addresses(
        (int64_t)(uintptr_t)func_table_ptr, num_funcs) : NULL;
    if (ctx_runtime(ctx)->gc_func_table) moonbit_decref(ctx_runtime(ctx)->gc_func_table);
    ctx_runtime(ctx)->gc_func_table = copy;
    ctx_runtime(ctx)->gc_func_table_size = num_funcs;
}

void clear_type_cache_internal(jit_context_t *ctx) {
    if (!ctx) return;

    if (ctx_runtime(ctx)->gc_type_cache) {
        moonbit_decref(ctx_runtime(ctx)->gc_type_cache);
        ctx_runtime(ctx)->gc_type_cache = NULL;
    }
    ctx_runtime(ctx)->gc_num_types = 0;

    if (ctx_runtime(ctx)->gc_canonical_indices) {
        moonbit_decref(ctx_runtime(ctx)->gc_canonical_indices);
        ctx_runtime(ctx)->gc_canonical_indices = NULL;
    }
    ctx_runtime(ctx)->gc_num_canonical = 0;

    if (ctx_runtime(ctx)->gc_func_type_indices) {
        moonbit_decref(ctx_runtime(ctx)->gc_func_type_indices);
        ctx_runtime(ctx)->gc_func_type_indices = NULL;
    }
    ctx_runtime(ctx)->gc_num_funcs = 0;

    if (ctx_runtime(ctx)->gc_func_table) moonbit_decref(ctx_runtime(ctx)->gc_func_table);
    ctx_runtime(ctx)->gc_func_table = NULL;
    ctx_runtime(ctx)->gc_func_table_size = 0;
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(gc_ref_cast_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_ref_test_impl);
WASMOON_DEFINE_GUEST_TARGET(gc_type_check_subtype_impl);
#endif
