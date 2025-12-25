// Copyright 2025
// GC type cache and type checking for JIT runtime
// Implements ref.test, ref.cast, and subtype checking

#include "jit_internal.h"

// ============ Global Type Cache State ============

int32_t *g_gc_type_cache = NULL;
int g_gc_num_types = 0;
int32_t *g_gc_canonical_indices = NULL;
int g_gc_num_canonical = 0;
int32_t *g_func_type_indices = NULL;
int g_num_funcs = 0;
void **g_func_table = NULL;
int g_func_table_size = 0;

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

// ============ Subtype Checking ============

int is_subtype_cached(int type1, int type2) {
    if (type1 == type2) return 1;
    if (type1 < 0 || type1 >= g_gc_num_types) return 0;
    if (type2 < 0 || type2 >= g_gc_num_types) return 0;

    // Check canonical indices first (if available)
    if (g_gc_canonical_indices && g_gc_num_canonical > 0) {
        if (type1 < g_gc_num_canonical && type2 < g_gc_num_canonical) {
            if (g_gc_canonical_indices[type1] == g_gc_canonical_indices[type2]) {
                return 1;
            }
        }
    }

    // Walk the supertype chain
    int current = type1;
    while (current >= 0 && current < g_gc_num_types) {
        if (current == type2) return 1;
        int super_idx = g_gc_type_cache[current * 3];  // offset 0 = super_idx
        if (super_idx < 0) break;  // No more supertypes
        if (super_idx == current) break;  // Avoid infinite loop
        current = super_idx;
    }
    return 0;
}

// ============ ref.test Implementation ============

int32_t gc_ref_test_impl(int64_t value, int32_t type_idx, int32_t nullable) {
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
            default:
                // For concrete type indices, check if the function's type is a subtype
                {
                    int32_t func_idx = -1;

                    if (value < 0) {
                        // IR-encoded funcref: value = -(func_idx + 1)
                        func_idx = (int32_t)(-(value + 1));
                    } else if (is_funcref_ptr_value(value) && g_func_table && g_func_table_size > 0) {
                        // Tagged pointer funcref: search func_table for the ptr
                        void* raw_ptr = (void*)(value & ~FUNCREF_TAG);
                        for (int i = 0; i < g_func_table_size; i++) {
                            if (g_func_table[i] == raw_ptr) {
                                func_idx = i;
                                break;
                            }
                        }
                    }

                    if (func_idx >= 0 && func_idx < g_num_funcs &&
                        g_func_type_indices && g_gc_type_cache) {
                        int32_t func_type_idx = g_func_type_indices[func_idx];
                        if (func_type_idx >= 0 && func_type_idx < g_gc_num_types &&
                            type_idx >= 0 && type_idx < g_gc_num_types) {
                            int32_t target_canonical = g_gc_canonical_indices ?
                                g_gc_canonical_indices[type_idx] : type_idx;

                            int32_t current_type = func_type_idx;
                            while (current_type >= 0 && current_type < g_gc_num_types) {
                                int32_t current_canonical = g_gc_canonical_indices ?
                                    g_gc_canonical_indices[current_type] : current_type;
                                if (current_canonical == target_canonical) {
                                    return 1;
                                }
                                int32_t super_idx = g_gc_type_cache[current_type * 3];
                                if (super_idx < 0 || super_idx == current_type) break;
                                current_type = super_idx;
                            }
                        }
                    }
                }
                return 0;
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
    if (!is_heap_ref_value(value)) {
        return 0;
    }

    int32_t gc_ref = (int32_t)(value >> 1);
    if (gc_ref <= 0 || !g_gc_heap) {
        return 0;
    }

    int32_t obj_kind = gc_heap_get_kind(g_gc_heap, gc_ref);
    int32_t obj_type_idx = gc_heap_get_type_idx(g_gc_heap, gc_ref);

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

    // Handle concrete type: check subtyping with canonical indices
    if (g_gc_type_cache && obj_type_idx >= 0 && obj_type_idx < g_gc_num_types &&
        type_idx >= 0 && type_idx < g_gc_num_types) {
        int32_t target_canonical = g_gc_canonical_indices ?
            g_gc_canonical_indices[type_idx] : type_idx;

        int32_t current_type = obj_type_idx;
        while (current_type >= 0 && current_type < g_gc_num_types) {
            int32_t current_canonical = g_gc_canonical_indices ?
                g_gc_canonical_indices[current_type] : current_type;
            if (current_canonical == target_canonical) {
                return 1;
            }
            int32_t super_idx = g_gc_type_cache[current_type * 3];
            if (super_idx < 0 || super_idx == current_type) break;
            current_type = super_idx;
        }
    }

    return 0;
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
    if (is_subtype_cached(actual_type, expected_type)) {
        return;
    }

    // Types don't match - trap
    g_trap_code = 4;  // Indirect call type mismatch
    if (g_trap_active) {
        siglongjmp(g_trap_jmp_buf, 1);
    }
}

// ============ Type Cache Management ============

void set_type_cache_internal(int32_t *types_data, int num_types) {
    if (g_gc_type_cache) {
        free(g_gc_type_cache);
    }

    g_gc_num_types = num_types;
    if (num_types > 0 && types_data) {
        g_gc_type_cache = (int32_t*)malloc(num_types * 3 * sizeof(int32_t));
        if (g_gc_type_cache) {
            memcpy(g_gc_type_cache, types_data, num_types * 3 * sizeof(int32_t));
        }
    } else {
        g_gc_type_cache = NULL;
    }
}

void set_canonical_indices_internal(int32_t *canonical, int num_types) {
    if (g_gc_canonical_indices) {
        free(g_gc_canonical_indices);
    }

    g_gc_num_canonical = num_types;
    if (num_types > 0 && canonical) {
        g_gc_canonical_indices = (int32_t*)malloc(num_types * sizeof(int32_t));
        if (g_gc_canonical_indices) {
            memcpy(g_gc_canonical_indices, canonical, num_types * sizeof(int32_t));
        }
    } else {
        g_gc_canonical_indices = NULL;
    }
}

void set_func_type_indices_internal(int32_t *indices, int num_funcs) {
    if (g_func_type_indices) {
        free(g_func_type_indices);
    }

    g_num_funcs = num_funcs;
    if (num_funcs > 0 && indices) {
        g_func_type_indices = (int32_t*)malloc(num_funcs * sizeof(int32_t));
        if (g_func_type_indices) {
            memcpy(g_func_type_indices, indices, num_funcs * sizeof(int32_t));
        }
    } else {
        g_func_type_indices = NULL;
    }
}

void set_func_table_internal(void **func_table_ptr, int num_funcs) {
    g_func_table = func_table_ptr;
    g_func_table_size = num_funcs;
}

void clear_type_cache_internal(void) {
    if (g_gc_type_cache) {
        free(g_gc_type_cache);
        g_gc_type_cache = NULL;
    }
    g_gc_num_types = 0;

    if (g_gc_canonical_indices) {
        free(g_gc_canonical_indices);
        g_gc_canonical_indices = NULL;
    }
    g_gc_num_canonical = 0;

    if (g_func_type_indices) {
        free(g_func_type_indices);
        g_func_type_indices = NULL;
    }
    g_num_funcs = 0;

    g_func_table = NULL;
    g_func_table_size = 0;
}
