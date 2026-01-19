// Copyright 2025
// Exception handling for JIT runtime
// Implements WebAssembly exception handling using setjmp/longjmp

// Ensure POSIX setjmp APIs are declared on glibc.
// This is required for `sigsetjmp` to be visible in some feature-macro configurations.
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <setjmp.h>

#include "jit_internal.h"

// ============ Exception Handler Management ============

sigjmp_buf* exception_try_begin_impl(jit_context_t *ctx, int32_t handler_id) {
    // Allocate new handler node
    exception_handler_t *handler = (exception_handler_t *)malloc(sizeof(exception_handler_t));
    if (!handler) {
        // Out of memory - trap
        g_trap_code = 99;
        siglongjmp(g_trap_jmp_buf, 1);
    }

    // Link to previous handler
    handler->prev = (exception_handler_t *)ctx->exception_handler;
    handler->handler_id = handler_id;
    ctx->exception_handler = handler;

    // Return pointer to jmp_buf for caller to call setjmp
    return &handler->jmp_buf;
}

void exception_try_end_impl(jit_context_t *ctx, int32_t handler_id) {
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;

    // Pop handler from chain (should match handler_id)
    if (handler && handler->handler_id == handler_id) {
        ctx->exception_handler = handler->prev;
        free(handler);
    }

    // Clear any pending exception values
    if (ctx->exception_values) {
        free(ctx->exception_values);
        ctx->exception_values = NULL;
    }
    ctx->exception_value_count = 0;

    // Clear any spilled locals
    if (ctx->spilled_locals) {
        free(ctx->spilled_locals);
        ctx->spilled_locals = NULL;
    }
    ctx->spilled_locals_count = 0;
}

// ============ Exception Throwing ============

void exception_throw_impl(jit_context_t *ctx, int32_t tag_addr,
                          int64_t *values, int32_t count) {
    // Free any previous exception values
    if (ctx->exception_values) {
        free(ctx->exception_values);
        ctx->exception_values = NULL;
    }

    // Store exception info
    ctx->exception_tag = tag_addr;
    ctx->exception_value_count = count;

    if (count > 0 && values) {
        // Copy exception values to heap
        ctx->exception_values = (int64_t *)malloc(count * sizeof(int64_t));
        if (ctx->exception_values) {
            memcpy(ctx->exception_values, values, count * sizeof(int64_t));
        }
    } else {
        ctx->exception_values = NULL;
    }

    // Find handler and longjmp
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;
    if (handler) {
        siglongjmp(handler->jmp_buf, handler->handler_id);
    }

    // No handler - propagate as trap (uncaught exception)
    // Use trap code 8 for uncaught exception
    g_trap_code = 8;
    siglongjmp(g_trap_jmp_buf, 1);
}

void exception_throw_ref_impl(jit_context_t *ctx, int64_t exnref) {
    // exnref encodes the exception reference from a catch_ref block.
    // The exception values are already stored in ctx from when it was caught,
    // so we just re-throw by jumping to the current handler.
    (void)exnref; // exnref is implicit in ctx's exception state
    exception_handler_t *handler = (exception_handler_t *)ctx->exception_handler;
    if (handler) {
        siglongjmp(handler->jmp_buf, handler->handler_id);
    }

    // No handler - uncaught exception trap
    g_trap_code = 8;
    siglongjmp(g_trap_jmp_buf, 1);
}

void exception_delegate_impl(jit_context_t *ctx, int32_t depth) {
    // Delegate skips 'depth' handlers and throws to the one at that level
    exception_handler_t *target = (exception_handler_t *)ctx->exception_handler;

    // Walk up the handler chain by depth
    for (int i = 0; i < depth && target; i++) {
        // Pop this handler (we're delegating past it)
        exception_handler_t *to_free = target;
        target = target->prev;
        ctx->exception_handler = target;
        free(to_free);
    }

    if (target) {
        // longjmp to target handler
        siglongjmp(target->jmp_buf, target->handler_id);
    }

    // No handler at that depth - uncaught exception
    g_trap_code = 8;
    siglongjmp(g_trap_jmp_buf, 1);
}

// ============ Locals Spilling for Exception Handling ============

void exception_spill_locals_impl(jit_context_t *ctx, int64_t *locals, int32_t count) {
    // Free any previous spilled locals
    if (ctx->spilled_locals) {
        free(ctx->spilled_locals);
        ctx->spilled_locals = NULL;
    }

    ctx->spilled_locals_count = count;

    if (count > 0 && locals) {
        // Copy locals to heap
        ctx->spilled_locals = (int64_t *)malloc(count * sizeof(int64_t));
        if (ctx->spilled_locals) {
            memcpy(ctx->spilled_locals, locals, count * sizeof(int64_t));
        }
    } else {
        ctx->spilled_locals = NULL;
    }
}

int64_t exception_get_spilled_local_impl(jit_context_t *ctx, int32_t idx) {
    if (idx >= 0 && idx < ctx->spilled_locals_count && ctx->spilled_locals) {
        return ctx->spilled_locals[idx];
    }
    return 0;  // Return 0 for out-of-bounds access
}

// ============ Exception Value Access ============

int32_t exception_get_tag_impl(jit_context_t *ctx) {
    return ctx->exception_tag;
}

int64_t exception_get_value_impl(jit_context_t *ctx, int32_t idx) {
    if (idx >= 0 && idx < ctx->exception_value_count && ctx->exception_values) {
        return ctx->exception_values[idx];
    }
    return 0;  // Return 0 for out-of-bounds access
}

int32_t exception_get_value_count_impl(jit_context_t *ctx) {
    return ctx->exception_value_count;
}

// ============ FFI Exports ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exception_try_begin(int64_t ctx_ptr, int32_t handler_id) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return (int64_t)exception_try_begin_impl(ctx, handler_id);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_try_end(int64_t ctx_ptr, int32_t handler_id) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_try_end_impl(ctx, handler_id);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw(int64_t ctx_ptr, int32_t tag_addr,
                                                     int64_t values_ptr, int32_t count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    int64_t *values = (int64_t *)values_ptr;
    exception_throw_impl(ctx, tag_addr, values, count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_throw_ref(int64_t ctx_ptr, int64_t exnref) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_throw_ref_impl(ctx, exnref);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_exception_delegate(int64_t ctx_ptr, int32_t depth) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    exception_delegate_impl(ctx, depth);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_get_tag(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_tag_impl(ctx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exception_get_value(int64_t ctx_ptr, int32_t idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_value_impl(ctx, idx);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_exception_get_value_count(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_value_count_impl(ctx);
}

// Get function pointers for JIT codegen
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_try_begin_ptr(void) {
    return (int64_t)wasmoon_jit_exception_try_begin;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_try_end_ptr(void) {
    return (int64_t)wasmoon_jit_exception_try_end;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_ptr(void) {
    return (int64_t)wasmoon_jit_exception_throw;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_throw_ref_ptr(void) {
    return (int64_t)wasmoon_jit_exception_throw_ref;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_delegate_ptr(void) {
    return (int64_t)wasmoon_jit_exception_delegate;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_tag_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_tag;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_value_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_value;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_value_count_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_value_count;
}

// Spill/restore locals for exception handling
MOONBIT_FFI_EXPORT void wasmoon_jit_exception_spill_locals(int64_t ctx_ptr,
                                                            int64_t locals_ptr, int32_t count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    int64_t *locals = (int64_t *)locals_ptr;
    exception_spill_locals_impl(ctx, locals, count);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exception_get_spilled_local(int64_t ctx_ptr, int32_t idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return exception_get_spilled_local_impl(ctx, idx);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_spill_locals_ptr(void) {
    return (int64_t)wasmoon_jit_exception_spill_locals;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_exception_get_spilled_local_ptr(void) {
    return (int64_t)wasmoon_jit_exception_get_spilled_local;
}

// Get sigsetjmp function pointer for JIT to call directly.
//
// IMPORTANT: do NOT wrap sigsetjmp in another C function.
// The JIT calls setjmp inside the *current* wasm frame and later longjmps back
// into that exact frame. If setjmp is performed in a wrapper that returns, the
// saved environment becomes invalid (undefined behavior) and longjmp may crash.
//
// On glibc, `sigsetjmp` may be a macro, so taking its address can be brittle.
// We return the address of the underlying implementation when available.
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sigsetjmp_ptr(void) {
#if defined(__GLIBC__)
    // glibc exposes the underlying implementation as __sigsetjmp.
    extern int __sigsetjmp(sigjmp_buf env, int savemask);
    return (int64_t)__sigsetjmp;
#else
    return (int64_t)sigsetjmp;
#endif
}
