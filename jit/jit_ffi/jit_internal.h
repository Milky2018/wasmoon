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

extern __thread sigjmp_buf g_trap_jmp_buf;
extern __thread volatile sig_atomic_t g_trap_code;
extern __thread volatile sig_atomic_t g_trap_active;
extern __thread volatile sig_atomic_t g_trap_signal;
extern __thread volatile uintptr_t g_trap_pc;
extern __thread volatile uintptr_t g_trap_lr;
extern __thread volatile uintptr_t g_trap_fp;
extern __thread volatile uintptr_t g_trap_frame_lr;
extern __thread volatile uintptr_t g_trap_fault_addr;
extern __thread volatile sig_atomic_t g_trap_brk_imm;
extern __thread volatile sig_atomic_t g_trap_func_idx;
extern __thread volatile uintptr_t g_trap_wasm_stack_base;
extern __thread volatile uintptr_t g_trap_wasm_stack_top;

// Pre-captured frame chain (captured in signal handler)
#define MAX_TRAP_FRAMES 32
extern __thread volatile uintptr_t g_trap_frames_pc[MAX_TRAP_FRAMES];
extern __thread volatile uintptr_t g_trap_frames_fp[MAX_TRAP_FRAMES];
extern __thread volatile int g_trap_frame_count;

void install_trap_handler(void);

// ============ Executable Memory (exec_mem.c) ============

int64_t alloc_exec_internal(int size);
int copy_code_internal(int64_t dest, const uint8_t *src, int size);
int free_exec_internal(int64_t ptr);

// ============ JIT Context (jit_context.c) ============

// Context allocation/free (internal implementations)
jit_context_t *alloc_context_internal(int func_count);
void free_context_internal(jit_context_t *ctx);
void wasmoon_jit_free_wasi_fds(int64_t ctx_ptr);

// ============ Memory Operations (memory_ops.c) ============

// Free a `wasmoon_memory_t` descriptor (jit.c)
void wasmoon_jit_free_memory_desc(int64_t mem_ptr);

#define WASM_PAGE_SIZE 65536

// Guard page memory allocation (for bounds check elimination)
uint8_t *alloc_guarded_memory_external(wasmoon_memory_t *memory, size_t initial_size, size_t max_size);
int is_memory_guard_page_access(jit_context_t *ctx, void *addr);

// v3 ctx-passing (re-entrant) variants (internal implementations)
// These operate on memory 0 (fast path, backward compatible)
int32_t memory_grow_ctx_internal(jit_context_t *ctx, int32_t delta, int32_t max_pages);
int32_t memory_size_ctx_internal(jit_context_t *ctx);
void memory_fill_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t val, int32_t size);
void memory_copy_ctx_internal(jit_context_t *ctx, int32_t dst, int32_t src, int32_t size);

// v4 multi-memory variants (with memidx parameter)
int32_t memory_grow_indexed_internal(jit_context_t *ctx, int32_t memidx, int32_t delta, int32_t max_pages);
int32_t memory_size_indexed_internal(jit_context_t *ctx, int32_t memidx);
void memory_fill_indexed_internal(jit_context_t *ctx, int32_t memidx, int32_t dst, int32_t val, int32_t size);
void memory_copy_indexed_internal(jit_context_t *ctx, int32_t dst_memidx, int32_t src_memidx,
                                   int32_t dst, int32_t src, int32_t size);

// Descriptor-only variants (no ctx)
int32_t memory_grow_desc_internal(wasmoon_memory_t *mem, int32_t delta, int32_t max_pages);
int64_t memory_len_desc_internal(wasmoon_memory_t *mem);
uint8_t *memory_base_desc_internal(wasmoon_memory_t *mem);

// Table operations
int32_t table_grow_ctx_internal(jit_context_t *ctx, int32_t table_idx, int64_t delta, int64_t init_value);

// GC heap management
void ctx_set_gc_heap_internal(jit_context_t *ctx, GcHeap *heap);
void ctx_update_gc_heap_ptr_internal(jit_context_t *ctx);

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

// ============ Exception Handling (exception.c) ============

// Exception handler structure (linked list for nested try blocks)
typedef struct exception_handler {
    sigjmp_buf jmp_buf;               // longjmp target
    struct exception_handler *prev;    // Outer handler (linked list)
    int32_t handler_id;                // Unique ID for this handler
} exception_handler_t;

// Exception handling functions
sigjmp_buf* exception_try_begin_impl(jit_context_t *ctx, int32_t handler_id);
void exception_try_end_impl(jit_context_t *ctx, int32_t handler_id);
void exception_throw_impl(jit_context_t *ctx, int32_t tag_addr,
                          int64_t *values, int32_t count) __attribute__((noreturn));
void exception_throw_ref_impl(jit_context_t *ctx, int64_t exnref) __attribute__((noreturn));
void exception_delegate_impl(jit_context_t *ctx, int32_t depth) __attribute__((noreturn));
int32_t exception_get_tag_impl(jit_context_t *ctx);
int64_t exception_get_value_impl(jit_context_t *ctx, int32_t idx);
int32_t exception_get_value_count_impl(jit_context_t *ctx);
void exception_spill_locals_impl(jit_context_t *ctx, int64_t *locals, int32_t count);
int64_t exception_get_spilled_local_impl(jit_context_t *ctx, int32_t idx);

// ============ WASM Stack (wasm_stack.c) ============

// Check if an address is in the WASM stack guard page
int is_wasm_guard_page_access(jit_context_t *ctx, void *addr);

// Get current JIT context (thread-local, set during stack-switching calls)
jit_context_t *get_current_jit_context(void);

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

// Inline allocation support (for JIT fast path)
int64_t gc_register_struct_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size);
int64_t gc_register_array_inline(jit_context_t *ctx, uint8_t *obj_ptr, int32_t total_size);
int64_t gc_alloc_struct_slow(jit_context_t *ctx, int32_t type_idx,
                              int64_t *fields, int32_t num_fields);
int64_t gc_alloc_array_slow(jit_context_t *ctx, int32_t type_idx,
                             int32_t len, int64_t init_value);

#endif // JIT_INTERNAL_H
