#ifndef WASMOON_EXCEPTION_H
#define WASMOON_EXCEPTION_H

#include <setjmp.h>
#include "../abi/windows_context.h"
#include "../context/jit_context.h"
#include "../gc/gc_heap.h"

// Exception handler structure (linked list for nested try blocks)
typedef struct exception_handler {
    sigjmp_buf jmp_buf;               // longjmp target
    struct exception_handler *prev;    // Outer handler (linked list)
    int32_t handler_id;                // Unique ID for this handler
    wasmoon_gc_root_scope_t *gc_root_scope_marker;
    wasmoon_gc_function_frame_t *gc_function_frame_marker;
} exception_handler_t;

// Managed callbacks stage exceptions; only native guest frames may unwind.
int jit_hostcall_is_active(const jit_context_t *ctx);
int exception_has_pending_hostcall(jit_context_t *ctx);
void exception_raise_pending_hostcall(jit_context_t *ctx);

// Exception handling functions
#if defined(_MSC_VER) && !defined(__clang__)
#define WASMOON_NORETURN __declspec(noreturn)
#else
#define WASMOON_NORETURN __attribute__((noreturn))
#endif
sigjmp_buf* exception_try_begin_impl(jit_context_t *ctx, int32_t handler_id);
void exception_try_end_impl(jit_context_t *ctx, int32_t handler_id);
WASMOON_NORETURN void exception_throw_impl(jit_context_t *ctx, int32_t tag_addr,
                          int64_t *values, int32_t count);
WASMOON_NORETURN void exception_throw_ref_impl(jit_context_t *ctx, int64_t exnref);
WASMOON_NORETURN void exception_delegate_impl(jit_context_t *ctx, int32_t depth);
int32_t exception_get_tag_impl(jit_context_t *ctx);
int64_t exception_get_value_impl(jit_context_t *ctx, int32_t idx);
int32_t exception_get_value_count_impl(jit_context_t *ctx);
void exception_mark_activation_roots(GcHeap *heap, jit_context_t *ctx, const jit_execution_state_t *state);
int32_t exception_copy_activation_roots(jit_context_t *ctx, const jit_execution_state_t *state,
    int64_t *roots, int32_t capacity);
void exception_spill_locals_impl(jit_context_t *ctx, int64_t *locals, int32_t count);
int64_t exception_get_spilled_local_impl(jit_context_t *ctx, int32_t idx);

void exception_arena_release(struct native_exception_arena *arena);

int64_t exception_capture_payload(jit_context_t *ctx, int32_t tag, const int64_t *values, int32_t count);
int64_t exception_try_capture_payload(jit_context_t *ctx, int32_t tag, const int64_t *values, int32_t count);
int64_t exception_capture_current(jit_context_t *ctx);

#endif
