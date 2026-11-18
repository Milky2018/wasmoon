#ifndef WASMOON_GC_TYPES_H
#define WASMOON_GC_TYPES_H

#include "../context/jit_ffi.h"

// Abstract type indices (negative values)
#define ABSTRACT_TYPE_ANY      (-1)   // anyref
#define ABSTRACT_TYPE_EQ       (-2)   // eqref
#define ABSTRACT_TYPE_I31      (-3)   // i31ref
#define ABSTRACT_TYPE_STRUCT   (-4)   // structref (abstract)
#define ABSTRACT_TYPE_ARRAY    (-5)   // arrayref (abstract)
#define ABSTRACT_TYPE_FUNC     (-6)   // funcref
#define ABSTRACT_TYPE_EXTERN   (-7)   // externref
#define ABSTRACT_TYPE_NONE     (-8)   // nullref (bottom type for any)
#define ABSTRACT_TYPE_NOFUNC   (-9)   // nofunc (bottom type for func)
#define ABSTRACT_TYPE_NOEXTERN (-10)  // noextern (bottom type for extern)

// Type kind constants
#define GC_KIND_FUNC   0
#define GC_KIND_STRUCT 1
#define GC_KIND_ARRAY  2

// Type cache layout (per type) used by JIT libcalls.
// Keep this in sync with `gc_helpers.mbt` (gc_type_data).
#define GC_TYPE_CACHE_STRIDE 6
#define GC_TYPE_SUPER_IDX_OFF 0
#define GC_TYPE_KIND_OFF 1
#define GC_TYPE_STRUCT_NUM_FIELDS_OFF 2
#define GC_TYPE_ARRAY_ELEM_TAG_OFF 3
#define GC_TYPE_ARRAY_ELEM_BYTES_OFF 4
#define GC_TYPE_ARRAY_ELEM_FLAGS_OFF 5

// Value encoding tags
#define EXTERNREF_TAG 0x4000000000000000LL
#define FUNCREF_TAG   0x2000000000000000LL
#define STORE_FUNCREF_TAG 0x3000000000000000LL
#define REF_TAGS_MASK (EXTERNREF_TAG | FUNCREF_TAG)

// Type checking functions
int is_subtype_cached(int type1, int type2);
int32_t WASMOON_GUEST_ABI gc_ref_test_impl(jit_context_t *ctx, int64_t value, int32_t type_idx, int32_t nullable);
int64_t WASMOON_GUEST_ABI gc_ref_cast_impl(jit_context_t *ctx, int64_t value, int32_t type_idx, int32_t nullable);
void WASMOON_GUEST_ABI gc_type_check_subtype_impl(jit_context_t *ctx, int32_t actual_type, int32_t expected_type);

// Type cache management
void clear_type_cache_internal(jit_context_t *ctx);

#endif
