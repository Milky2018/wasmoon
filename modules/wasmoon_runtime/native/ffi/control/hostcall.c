// Copyright 2025
#include "hostcall.h"
#include "trap.h"
#include "fiber.h"
#include "exception.h"
#include "../../ownership/ffi_callbacks.h"
#include <string.h>
#include <stdlib.h>

// ============ Hostcall Bridge (JIT -> Host) ============
// Thread-local scratch for the currently executing hostcall.
// This is read by the MoonBit dispatcher via FFI getters.
static _Thread_local int32_t g_hostcall_func_idx = -1;
static _Thread_local int64_t g_hostcall_values_ptr = 0;
static _Thread_local int32_t g_hostcall_num_args = 0;
static _Thread_local int32_t g_hostcall_num_results = 0;

// ============ Hostcall Callback Registration ============

typedef int32_t (*hostcall_callback_fn)(void *closure);

// MoonBit's C backend gives each closure signature a generated nominal struct
// tag. FuncRef erases that tag at the separately compiled native-stub boundary,
// while its extern declaration still fixes the pointer and result ABI. Disable
// only Clang's nominal indirect-function check at this call seam.
static _Thread_local jit_context_t *g_hostcall_context = NULL;

int jit_hostcall_is_active(const jit_context_t *ctx) {
    return ctx && g_hostcall_context == ctx;
}

static WASMOON_NO_FUNCTION_SANITIZE int32_t call_hostcall_callback(
    jit_context_t *ctx,
    hostcall_callback_fn callback,
    void *closure
) {
    jit_context_t *previous = g_hostcall_context;
    // The callback may replace or clear its own registration.
    if (closure) moonbit_incref(closure);
    g_hostcall_context = ctx;
    int32_t status = callback(closure);
    g_hostcall_context = previous;
    if (closure) moonbit_decref(closure);
    return status;
}

static void clear_hostcall_callback(jit_context_t *ctx) {
    if (!ctx) return;
    if (ctx_runtime(ctx)->hostcall_callback_data) {
        moonbit_decref(ctx_runtime(ctx)->hostcall_callback_data);
        ctx_runtime(ctx)->hostcall_callback_data = NULL;
    }
    ctx_runtime(ctx)->hostcall_callback = NULL;
}

// ============ Hostcall Execution ============

// Called by JIT-generated trampolines (C calling convention).
// The MoonBit callback returns before a suspension switches stacks, so no
// callback frame is retained by a parked native continuation.
static int hostcall_slots_in_range(
    uintptr_t ptr,
    uintptr_t bytes,
    uintptr_t base,
    uintptr_t top
) {
    if (base >= top || ptr < base || ptr > top) return 0;
    return bytes <= top - ptr;
}

MOONBIT_FFI_EXPORT int32_t WASMOON_GUEST_ABI wasmoon_jit_hostcall(
    jit_context_t *ctx,
    int32_t func_idx,
    int64_t values_ptr,
    int32_t num_args,
    int32_t num_results
) {
    if (!ctx || !ctx_runtime(ctx)->hostcall_callback) {
        g_trap_code = 3; // unreachable
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return (int32_t)g_trap_code;
    }
    // Defensive: hostcall trampolines pass a pointer into the active WASM stack.
    // If ABI bugs pass an invalid pointer, the MoonBit dispatcher may scribble
    // over unrelated memory and corrupt the heap.
    uintptr_t base = 0;
    uintptr_t top = 0;
    if (wasmoon_native_fiber_stack_bounds(
            &base, &top, NULL, NULL
        )) {
        uintptr_t ptr = (uintptr_t)values_ptr;
        // Each slot is 8 bytes; `num_args`/`num_results` are already slot counts
        // (v128 uses 2 slots in the trampoline).
        if (num_args < 0 || num_results < 0 ||
            num_args > INT32_MAX - num_results) {
            g_trap_code = 3;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return (int32_t)g_trap_code;
        }
        uintptr_t bytes = (uintptr_t)(num_args + num_results) * 8u;
        int valid = hostcall_slots_in_range(ptr, bytes, base, top);
        if (!valid) {
            g_trap_code = 3; // unreachable
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return (int32_t)g_trap_code;
        }
    }

    int32_t previous_func_idx = g_hostcall_func_idx;
    int64_t previous_values_ptr = g_hostcall_values_ptr;
    int32_t previous_num_args = g_hostcall_num_args;
    int32_t previous_num_results = g_hostcall_num_results;
    g_hostcall_func_idx = func_idx;
    g_hostcall_values_ptr = values_ptr;
    g_hostcall_num_args = num_args;
    g_hostcall_num_results = num_results;

    hostcall_callback_fn cb = (hostcall_callback_fn)ctx_runtime(ctx)->hostcall_callback;
    int32_t trap = call_hostcall_callback(
        ctx, cb, ctx_runtime(ctx)->hostcall_callback_data
    );
    while (trap == WASMOON_HOSTCALL_SUSPEND_STATUS &&
           !exception_has_pending_hostcall(ctx)) {
        // A parked fiber is not the dynamically active hostcall. Restore its
        // caller before yielding so nested native entry writes through the
        // caller's values buffer rather than this parked frame.
        g_hostcall_func_idx = previous_func_idx;
        g_hostcall_values_ptr = previous_values_ptr;
        g_hostcall_num_args = previous_num_args;
        g_hostcall_num_results = previous_num_results;
        int64_t resume = wasmoon_native_fiber_yield(
            WASMOON_FIBER_EVENT_HOSTCALL_SUSPENDED
        );
        // A continuation may be resumed from a different dynamic hostcall.
        // Capture that caller now instead of retaining the caller that was
        // active at the original suspension point.
        previous_func_idx = g_hostcall_func_idx;
        previous_values_ptr = g_hostcall_values_ptr;
        previous_num_args = g_hostcall_num_args;
        previous_num_results = g_hostcall_num_results;
        g_hostcall_func_idx = func_idx;
        g_hostcall_values_ptr = values_ptr;
        g_hostcall_num_args = num_args;
        g_hostcall_num_results = num_results;
        if (resume == INT64_MIN) {
            trap = 8;
        } else if (resume == 1) {
            cb = (hostcall_callback_fn)ctx_runtime(ctx)->hostcall_callback;
            if (!cb) {
                trap = 8;
                break;
            }
            trap = call_hostcall_callback(
                ctx, cb, ctx_runtime(ctx)->hostcall_callback_data
            );
        } else {
            trap = 0;
        }
    }
    g_hostcall_func_idx = previous_func_idx;
    g_hostcall_values_ptr = previous_values_ptr;
    g_hostcall_num_args = previous_num_args;
    g_hostcall_num_results = previous_num_results;
    exception_raise_pending_hostcall(ctx);
    if (trap != 0) {
        g_trap_code = trap;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
    }
    return trap;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_hostcall_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_hostcall);
}

// ============ Cooperative Cancellation ============

typedef int32_t (*cancellation_callback_fn)(void *closure);

static WASMOON_NO_FUNCTION_SANITIZE int32_t call_cancellation_callback(
    cancellation_callback_fn callback,
    void *closure
) {
    return callback(closure);
}

static void clear_cancellation_callback(jit_context_t *ctx) {
    if (!ctx) return;
    if (ctx_runtime(ctx)->control_defaults.cancellation_callback_data) {
        moonbit_decref(ctx_runtime(ctx)->control_defaults.cancellation_callback_data);
        ctx_runtime(ctx)->control_defaults.cancellation_callback_data = NULL;
    }
    ctx_runtime(ctx)->control_defaults.cancellation_callback = NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_cancellation_callback(
    int64_t ctx_ptr,
    cancellation_callback_fn callback,
    void *closure
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) {
        if (closure) moonbit_decref(closure);
        return;
    }
    clear_cancellation_callback(ctx);
    ctx_runtime(ctx)->control_defaults.cancellation_callback = (void *)callback;
    ctx_runtime(ctx)->control_defaults.cancellation_callback_data = closure;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_cancellation_callback(int64_t ctx_ptr) {
    clear_cancellation_callback((jit_context_t *)ctx_ptr);
}

jit_invocation_controls_t *jit_execution_controls(jit_context_t *ctx) {
    jit_trap_activation_t *activation = jit_current_trap_activation();
    return activation->active ? activation->controls :
        (ctx ? &ctx_runtime(ctx)->control_defaults : NULL);
}

static int cancellation_requested(jit_invocation_controls_t *controls) {
    if (!controls || !controls->cancellation_callback) return 0;
    cancellation_callback_fn cb =
        (cancellation_callback_fn)controls->cancellation_callback;
    return call_cancellation_callback(cb, controls->cancellation_callback_data) != 0;
}

int wasmoon_jit_cancellation_requested(jit_context_t *ctx) {
    return cancellation_requested(jit_execution_controls(ctx));
}

MOONBIT_FFI_EXPORT int32_t WASMOON_GUEST_ABI wasmoon_jit_cancel_poll(jit_context_t *ctx) {
    jit_invocation_controls_t *controls = jit_execution_controls(ctx);
    if (cancellation_requested(controls)) {
        g_trap_code = 11;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 11;
    }
    // A MoonBit cancellation callback has returned before the native stack is
    // parked. Only compiled guest/C frames are retained by this suspension.
    if (controls && controls->scheduling_budget > 0 && --controls->scheduling_budget == 0) {
        controls->scheduling_budget = controls->scheduling_quantum > 0 ? controls->scheduling_quantum : 1024;
        if (wasmoon_native_fiber_yield(WASMOON_FIBER_EVENT_GUEST_YIELD) == INT64_MIN) {
            g_trap_code = 8;
            if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
            return 8;
        }
    }
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_cancel_poll_ptr(void) {
    return WASMOON_GUEST_ADDRESS(wasmoon_jit_cancel_poll);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_get_hostcall_func_idx(void) {
    return g_hostcall_func_idx;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_hostcall_values_ptr(void) {
    return g_hostcall_values_ptr;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_get_hostcall_num_args(void) {
    return g_hostcall_num_args;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_get_hostcall_num_results(void) {
    return g_hostcall_num_results;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_hostcall_callback_managed(
    void *jit_context,
    hostcall_callback_fn callback,
    void *closure
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) {
        if (closure) moonbit_decref(closure);
        return;
    }
    clear_hostcall_callback(ctx);
    ctx_runtime(ctx)->hostcall_callback = (void *)callback;
    ctx_runtime(ctx)->hostcall_callback_data = closure;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_hostcall_callback_managed(
    void *jit_context
) {
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_hostcall_callback(ctx);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_cancellation_callback_managed(
    void *jit_context,
    cancellation_callback_fn callback,
    void *closure
) {
    wasmoon_jit_set_cancellation_callback(
        wasmoon_jit_context_ptr(jit_context), callback, closure
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_cancellation_callback_managed(
    void *jit_context
) {
    wasmoon_jit_clear_cancellation_callback(wasmoon_jit_context_ptr(jit_context));
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_cooperative_scheduling_managed(void *context, int32_t enabled) {
    int64_t pointer = wasmoon_jit_context_ptr(context);
    jit_context_t *ctx = (void *)(uintptr_t)pointer;
    if (ctx) {
        jit_invocation_controls_t *controls = &ctx_runtime(ctx)->control_defaults;
        if (controls->scheduling_quantum <= 0) controls->scheduling_quantum = 1024;
        controls->scheduling_budget = enabled ? controls->scheduling_quantum : 0;
    }
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_set_cooperative_quantum_managed(void *object, int32_t quantum) {
    jit_context_t *ctx = (void *)(uintptr_t)wasmoon_jit_context_ptr(object);
    if (!ctx || quantum <= 0) return 0;
    jit_invocation_controls_t *controls = &ctx_runtime(ctx)->control_defaults;
    controls->scheduling_quantum = quantum;
    if (controls->scheduling_budget > 0) controls->scheduling_budget = quantum;
    return 1;
}

#if defined(_MSC_VER) && !defined(__clang__)
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_cancel_poll);
WASMOON_DEFINE_GUEST_TARGET(wasmoon_jit_hostcall);
#endif
