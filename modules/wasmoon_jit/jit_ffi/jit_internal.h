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
#include <pthread.h>
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
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
// 8 = backend trap
// 9 = out of memory
// 10 = GC precise roots unavailable
// 99 = unknown trap

#define MAX_TRAP_FRAMES 32

typedef struct jit_trap_activation {
    sigjmp_buf jmp_buf;
    volatile sig_atomic_t active;
    volatile sig_atomic_t code;
    volatile sig_atomic_t signal;
    volatile uintptr_t pc;
    volatile uintptr_t lr;
    volatile uintptr_t fp;
    volatile uintptr_t frame_lr;
    volatile uintptr_t fault_addr;
    volatile sig_atomic_t brk_imm;
    volatile sig_atomic_t func_idx;
    volatile uintptr_t x0;
    volatile uintptr_t x1;
    volatile uintptr_t x2;
    volatile uintptr_t x3;
    volatile uintptr_t x6;
    volatile uintptr_t x7;
    volatile uintptr_t x8;
    volatile uintptr_t x9;
    volatile uintptr_t x10;
    volatile uintptr_t x11;
    volatile uintptr_t x15;
    volatile uintptr_t stack_base;
    volatile uintptr_t stack_top;
    volatile uintptr_t guard_base;
    volatile size_t guard_size;
    volatile uintptr_t frames_pc[MAX_TRAP_FRAMES];
    volatile uintptr_t frames_fp[MAX_TRAP_FRAMES];
    volatile int frame_count;
    jit_context_t *context;
    struct jit_trap_activation *previous;
    void *exception_handler;
    int32_t exception_tag;
    int64_t *exception_values;
    int32_t exception_value_count;
    int64_t *spilled_locals;
    int32_t spilled_locals_count;
    wasmoon_gc_frame_t *gc_frame_chain_head;
    wasmoon_gc_root_scope_t *gc_root_scope_head;
    int32_t debug_current_func_idx;
    int context_detached;
} jit_trap_activation_t;

jit_trap_activation_t *jit_current_trap_activation(void);
jit_trap_activation_t *jit_observed_trap_activation(void);
void jit_trap_activation_init(
    jit_trap_activation_t *activation,
    jit_context_t *context
);
void jit_trap_activation_push(jit_trap_activation_t *activation);
void jit_trap_activation_publish(jit_trap_activation_t *activation);
void jit_trap_activation_pop(jit_trap_activation_t *activation);
jit_trap_activation_t *jit_trap_activation_detach(void);
void jit_trap_activation_attach(jit_trap_activation_t *activation);
void jit_trap_activation_abandon(jit_trap_activation_t *activation);

#define g_trap_jmp_buf (jit_current_trap_activation()->jmp_buf)
#define g_trap_active (jit_current_trap_activation()->active)
#define g_trap_code (jit_current_trap_activation()->code)
#define g_trap_signal (jit_current_trap_activation()->signal)
#define g_trap_pc (jit_current_trap_activation()->pc)
#define g_trap_lr (jit_current_trap_activation()->lr)
#define g_trap_fp (jit_current_trap_activation()->fp)
#define g_trap_frame_lr (jit_current_trap_activation()->frame_lr)
#define g_trap_fault_addr (jit_current_trap_activation()->fault_addr)
#define g_trap_brk_imm (jit_current_trap_activation()->brk_imm)
#define g_trap_func_idx (jit_current_trap_activation()->func_idx)
#define g_trap_x0 (jit_current_trap_activation()->x0)
#define g_trap_x1 (jit_current_trap_activation()->x1)
#define g_trap_x2 (jit_current_trap_activation()->x2)
#define g_trap_x3 (jit_current_trap_activation()->x3)
#define g_trap_x6 (jit_current_trap_activation()->x6)
#define g_trap_x7 (jit_current_trap_activation()->x7)
#define g_trap_x8 (jit_current_trap_activation()->x8)
#define g_trap_x9 (jit_current_trap_activation()->x9)
#define g_trap_x10 (jit_current_trap_activation()->x10)
#define g_trap_x11 (jit_current_trap_activation()->x11)
#define g_trap_x15 (jit_current_trap_activation()->x15)
#define g_trap_wasm_stack_base (jit_current_trap_activation()->stack_base)
#define g_trap_wasm_stack_top (jit_current_trap_activation()->stack_top)
#define g_trap_frames_pc (jit_current_trap_activation()->frames_pc)
#define g_trap_frames_fp (jit_current_trap_activation()->frames_fp)
#define g_trap_frame_count (jit_current_trap_activation()->frame_count)

void install_trap_handler(void);

int wasmoon_native_fiber_stack_bounds(
    uintptr_t *stack_base,
    uintptr_t *stack_top,
    uintptr_t *guard_base,
    size_t *guard_size
);
int64_t wasmoon_native_fiber_yield(int64_t value);

#define WASMOON_HOSTCALL_SUSPEND_STATUS (-1)
#define WASMOON_FIBER_EVENT_HOSTCALL_SUSPENDED INT64_C(0x57534d5355535001)

// ============ Executable Memory (exec_mem.c) ============

int64_t alloc_exec_internal(int size);
int copy_code_internal(int64_t dest, const uint8_t *src, int size);
int free_exec_internal(int64_t ptr);
int exec_block_count_internal(void);

// ============ JIT Context (jit_context.c) ============

// Context allocation/free (internal implementations)
jit_context_t *alloc_context_internal(int func_count);
void free_context_internal(jit_context_t *ctx);
void wasmoon_jit_free_wasi_fds(int64_t ctx_ptr);
void ctx_refresh_memory0_fast_fields(jit_context_t *ctx);

// ============ Memory Operations (memory_ops.c) ============

// Free a `wasmoon_memory_t` descriptor (jit.c)
void wasmoon_jit_free_memory_desc(int64_t mem_ptr);

#define WASM_PAGE_SIZE 65536

// Guard page memory allocation (for bounds check elimination)
uint8_t *alloc_guarded_memory_external(wasmoon_memory_t *memory, size_t initial_size, size_t max_size);
int is_memory_guard_page_access(jit_context_t *ctx, void *addr);

// Multi-memory variants (with memidx parameter)
int32_t memory_grow_indexed_internal(jit_context_t *ctx, int32_t memidx, int64_t delta, int32_t max_pages);
int32_t memory_size_indexed_internal(jit_context_t *ctx, int32_t memidx);
void memory_fill_indexed_internal(jit_context_t *ctx, int32_t memidx, int32_t dst, int32_t val, int32_t size);
void memory_copy_indexed_internal(jit_context_t *ctx, int32_t dst_memidx, int32_t src_memidx,
                                   int32_t dst, int32_t src, int32_t size);

// Descriptor-only variants (no ctx)
int32_t memory_grow_desc_internal(wasmoon_memory_t *mem, int32_t delta, int32_t max_pages);
int64_t memory_len_desc_internal(wasmoon_memory_t *mem);
uint8_t *memory_base_desc_internal(wasmoon_memory_t *mem);

// Table operations
int64_t table_grow_ctx_internal(jit_context_t *ctx, int32_t table_idx, int64_t delta, int64_t init_value);

// GC heap management
void ctx_set_gc_heap_internal(jit_context_t *ctx, GcHeap *heap);
void ctx_update_gc_heap_ptr_internal(jit_context_t *ctx);
void ctx_gc_begin_frame_internal(jit_context_t *ctx, uintptr_t frame_id);
void ctx_gc_end_frame_internal(jit_context_t *ctx);
int32_t ctx_gc_push_root_scope_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
);
void ctx_gc_pop_root_scope_internal(jit_context_t *ctx);
void ctx_gc_restore_root_scopes_internal(
    jit_context_t *ctx,
    wasmoon_gc_root_scope_t *marker
);
void ctx_gc_clear_root_scopes_internal(jit_context_t *ctx);
void ctx_gc_set_safepoint_table_internal(
    jit_context_t *ctx,
    const wasmoon_gc_safepoint_table_t *table
);
int32_t ctx_gc_set_func_safepoints_internal(
    jit_context_t *ctx,
    int32_t func_idx,
    const uint8_t *stackmap_blob,
    int32_t stackmap_blob_size,
    const int32_t *code_offsets,
    int32_t safepoint_count
);
void ctx_gc_use_func_safepoints_internal(
    jit_context_t *ctx,
    int32_t func_idx
);
int32_t ctx_gc_set_root_scratch_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
);
int32_t gc_collect_for_alloc_internal(
    jit_context_t *ctx,
    const int64_t *roots,
    int32_t root_count
);

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

// Type cache layout (per type) used by JIT libcalls.
// Keep this in sync with `jit/gc_helpers.mbt` (setup_type_cache_from_types).
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
#define REF_TAGS_MASK (EXTERNREF_TAG | FUNCREF_TAG)

// Type checking functions
int is_subtype_cached(int type1, int type2);
int32_t gc_ref_test_impl(int64_t value, int32_t type_idx, int32_t nullable);
int64_t gc_ref_cast_impl(int64_t value, int32_t type_idx, int32_t nullable);
void gc_type_check_subtype_impl(int32_t actual_type, int32_t expected_type);

// Type cache management
void set_type_cache_internal(jit_context_t *ctx, int32_t *types_data, int num_types);
void set_canonical_indices_internal(jit_context_t *ctx, int32_t *canonical, int num_types);
void set_func_type_indices_internal(jit_context_t *ctx, int32_t *indices, int num_funcs);
void set_func_table_internal(jit_context_t *ctx, void **func_table_ptr, int num_funcs);
void clear_type_cache_internal(jit_context_t *ctx);

// ============ Exception Handling (exception.c) ============

// Exception handler structure (linked list for nested try blocks)
typedef struct exception_handler {
    sigjmp_buf jmp_buf;               // longjmp target
    struct exception_handler *prev;    // Outer handler (linked list)
    int32_t handler_id;                // Unique ID for this handler
    wasmoon_gc_root_scope_t *gc_root_scope_marker;
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
void exception_reset_context_state(jit_context_t *ctx);

// ============ WASM Stack (wasm_stack.c) ============

// Check if an address is in the WASM stack guard page
int is_wasm_guard_page_access(jit_context_t *ctx, void *addr);

// Get current JIT context (thread-local, set during stack-switching calls)
jit_context_t *get_current_jit_context(void);

// ============ GC Operations (gc_ops.c) ============

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
                              int64_t *fields, int32_t num_fields, int32_t safepoint_id);
int64_t gc_alloc_array_slow(jit_context_t *ctx, int32_t type_idx,
                             int32_t len, int64_t init_value, int32_t safepoint_id);
int64_t gc_alloc_array_from_values_slow(jit_context_t *ctx, int32_t type_idx,
                                         int64_t *values, int32_t len, int32_t safepoint_id);

#endif // JIT_INTERNAL_H
