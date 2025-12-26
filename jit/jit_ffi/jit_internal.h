// Copyright 2025
// Internal header for JIT runtime implementation
// This file is included by all JIT implementation files but NOT exposed to MoonBit

#ifndef JIT_INTERNAL_H
#define JIT_INTERNAL_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <setjmp.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#endif
#endif

#include "moonbit.h"
#include "jit_ffi.h"
#include "gc_heap.h"

// ============ Trap Handling (trap.c) ============

// Trap codes (matching WebAssembly trap types):
// 0 = no trap
// 1 = out of bounds memory access
// 2 = call stack exhausted
// 3 = unreachable executed
// 4 = indirect call type mismatch
// 5 = invalid conversion to integer
// 6 = integer divide by zero
// 7 = integer overflow
// 99 = unknown trap

extern sigjmp_buf g_trap_jmp_buf;
extern volatile sig_atomic_t g_trap_code;
extern volatile sig_atomic_t g_trap_active;

void install_trap_handler(void);

// ============ Executable Memory (exec_mem.c) ============

int64_t alloc_exec_internal(int size);
int copy_code_internal(int64_t dest, const uint8_t *src, int size);
int free_exec_internal(int64_t ptr);

// ============ JIT Context (jit_context.c) ============

// Global JIT context (defined in jit_context.c)
// Note: g_jit_context is also declared in jit_ffi.h for wasi.c
extern void *g_jit_context_obj;

// Context allocation/free (internal implementations)
jit_context_t *alloc_context_internal(int func_count);
void free_context_internal(jit_context_t *ctx);

// ============ Memory Operations (memory_ops.c) ============

#define WASM_PAGE_SIZE 65536

int32_t memory_grow_internal(int32_t delta, int32_t max_pages);
int32_t memory_size_internal(void);
int64_t get_memory_base_internal(void);
int64_t get_memory_size_bytes_internal(void);
void memory_fill_internal(int32_t dst, int32_t val, int32_t size);
void memory_copy_internal(int32_t dst, int32_t src, int32_t size);
int32_t table_grow_internal(int32_t table_idx, int64_t delta, int64_t init_value);

// v3 ctx-passing (re-entrant) variants (internal implementations)
int32_t memory_grow_ctx_internal(jit_context_t *ctx, int32_t delta, int32_t max_pages);
int32_t memory_size_ctx_internal(jit_context_t *ctx);
void memory_fill_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t val, int32_t size);
void memory_copy_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t src, int32_t size);
int32_t table_grow_ctx_internal(jit_context_t *ctx, int32_t table_idx, int64_t delta, int64_t init_value);

// ============ GC Type Cache (gc_type_cache.c) ============

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

// Value encoding tags
#define EXTERNREF_TAG 0x4000000000000000LL
#define FUNCREF_TAG   0x2000000000000000LL
#define REF_TAGS_MASK (EXTERNREF_TAG | FUNCREF_TAG)

// Type cache globals
extern int32_t *g_gc_type_cache;
extern int g_gc_num_types;
extern int32_t *g_gc_canonical_indices;
extern int g_gc_num_canonical;
extern int32_t *g_func_type_indices;
extern int g_num_funcs;
extern void **g_func_table;
extern int g_func_table_size;

// Type checking functions
int is_subtype_cached(int type1, int type2);
int32_t gc_ref_test_impl(int64_t value, int32_t type_idx, int32_t nullable);
int64_t gc_ref_cast_impl(int64_t value, int32_t type_idx, int32_t nullable);
void gc_type_check_subtype_impl(int32_t actual_type, int32_t expected_type);

// Type cache management
void set_type_cache_internal(int32_t *types_data, int num_types);
void set_canonical_indices_internal(int32_t *canonical, int num_types);
void set_func_type_indices_internal(int32_t *indices, int num_funcs);
void set_func_table_internal(void **func_table_ptr, int num_funcs);
void clear_type_cache_internal(void);

// ============ GC Operations (gc_ops.c) ============

// GC heap pointer (set before JIT execution)
extern GcHeap *g_gc_heap;

// GC operation implementations
int64_t gc_struct_new_impl(int32_t type_idx, int64_t *fields, int32_t num_fields);
int64_t gc_struct_get_impl(int64_t ref, int32_t type_idx, int32_t field_idx);
void gc_struct_set_impl(int64_t ref, int32_t type_idx, int32_t field_idx, int64_t value);
int64_t gc_array_new_impl(int32_t type_idx, int32_t len, int64_t fill);
int64_t gc_array_get_impl(int64_t ref, int32_t type_idx, int32_t idx);
void gc_array_set_impl(int64_t ref, int32_t type_idx, int32_t idx, int64_t value);
int32_t gc_array_len_impl(int64_t ref);
void gc_array_fill_impl(int64_t ref, int32_t offset, int64_t value, int32_t count);
void gc_array_copy_impl(int64_t dst_ref, int32_t dst_offset,
                        int64_t src_ref, int32_t src_offset, int32_t count);

#endif // JIT_INTERNAL_H
