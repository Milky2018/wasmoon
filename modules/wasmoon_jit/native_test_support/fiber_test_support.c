#include "../jit_ffi/jit_internal.h"

#include <stdint.h>
#include <stdatomic.h>
#include <sys/wait.h>
#include <unistd.h>

typedef int64_t (*native_fiber_entry_fn)(void *closure);
typedef int32_t (*cancellation_callback_fn)(void *closure);

typedef struct {
    int64_t marker;
} callback_capture_t;

static _Atomic int callback_capture_releases;

static void finalize_callback_capture(void *self) {
    (void)self;
    atomic_fetch_add_explicit(
        &callback_capture_releases,
        1,
        memory_order_relaxed
    );
}

MOONBIT_FFI_EXPORT void *wasmoon_test_callback_capture_new(void) {
    callback_capture_t *capture = moonbit_make_external_object(
        finalize_callback_capture,
        sizeof(callback_capture_t)
    );
    if (!capture) return NULL;
    capture->marker = 0;
    return capture;
}

MOONBIT_FFI_EXPORT void wasmoon_test_callback_capture_touch(void *capture) {
    (void)capture;
}

MOONBIT_FFI_EXPORT void wasmoon_test_callback_capture_reset(void) {
    atomic_store_explicit(
        &callback_capture_releases,
        0,
        memory_order_relaxed
    );
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_callback_capture_release_count(void) {
    return atomic_load_explicit(
        &callback_capture_releases,
        memory_order_relaxed
    );
}

extern void wasmoon_jit_set_cancellation_callback(
    int64_t ctx_ptr,
    cancellation_callback_fn callback,
    void *closure
);

extern void *wasmoon_native_fiber_alloc(
    native_fiber_entry_fn entry,
    void *closure,
    int64_t stack_size
);
extern int wasmoon_native_fiber_continue(void *managed, int64_t resume_value);
extern int64_t wasmoon_native_fiber_return_value(void *managed);
extern int64_t wasmoon_test_native_fiber_register_probe(void *closure);
extern int32_t wasmoon_jit_hostcall(
    jit_context_t *ctx,
    int32_t func_idx,
    int64_t values_ptr,
    int32_t num_args,
    int32_t num_results
);

static int hostcall_probe_trampoline(
    jit_context_t *ctx,
    int64_t *values,
    void *func_ptr
) {
    values[0] = 10;
    int result = wasmoon_jit_hostcall(
        ctx,
        42,
        (int64_t)values,
        0,
        0
    );
    if (result != 0) return result;
    values[0] += 1;
    int mode = (int)(intptr_t)func_ptr;
    if (mode == 999) {
        ctx->debug_current_func_idx = mode;
        uintptr_t guard_base = 0;
        if (!wasmoon_native_fiber_stack_bounds(
                NULL, NULL, &guard_base, NULL
            )) {
            return 8;
        }
        volatile unsigned char *guard =
            (volatile unsigned char *)guard_base;
        *guard = 1;
        return 0;
    }
    if (mode > 1) {
        g_trap_func_idx = mode;
        g_trap_pc = (uintptr_t)hostcall_probe_trampoline;
        g_trap_code = 6;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_hostcall_probe_trampoline(void) {
    return (int64_t)hostcall_probe_trampoline;
}

static int fiber_stack_hostcall_probe(
    jit_context_t *ctx,
    int64_t *values,
    void *func_ptr
) {
    (void)func_ptr;
    uintptr_t fiber_base = 0;
    if (!wasmoon_native_fiber_stack_bounds(
            &fiber_base, NULL, NULL, NULL
        )) {
        values[0] = 3;
        return 3;
    }
    // AddressSanitizer may place fixed-size C locals on its fake stack. Use
    // the registered fiber mapping directly so this probe still exercises
    // the runtime's real native-fiber slot boundary under instrumentation.
    int64_t *slots = (int64_t *)fiber_base;
    int result = wasmoon_jit_hostcall(
        ctx,
        44,
        (int64_t)slots,
        0,
        0
    );
    values[0] = result;
    return result;
}

MOONBIT_FFI_EXPORT int64_t
wasmoon_test_fiber_stack_hostcall_probe_trampoline(void) {
    return (int64_t)fiber_stack_hostcall_probe;
}

static int nested_hostcall_tls_probe(
    jit_context_t *ctx,
    int64_t *values,
    void *func_ptr
) {
    (void)func_ptr;
    int64_t slots[1] = {0};
    int result = wasmoon_jit_hostcall(
        ctx,
        46,
        (int64_t)slots,
        0,
        1
    );
    values[0] = slots[0];
    return result;
}

MOONBIT_FFI_EXPORT int64_t
wasmoon_test_nested_hostcall_tls_probe_trampoline(void) {
    return (int64_t)nested_hostcall_tls_probe;
}

static int parked_gc_root_probe(
    jit_context_t *ctx,
    int64_t *values,
    void *func_ptr
) {
    (void)func_ptr;
    if (!ctx || !ctx->gc_heap || !values) return 8;
    if (!ctx_gc_push_root_scope_internal(ctx, values, 1)) return 9;
    int result = wasmoon_jit_hostcall(
        ctx,
        43,
        (int64_t)values,
        0,
        0
    );
    int64_t encoded = values[0];
    int32_t gc_ref = encoded > 0 && (encoded & 1L) == 0
        ? (int32_t)(encoded >> 1)
        : 0;
    values[1] = gc_heap_is_valid((GcHeap *)ctx->gc_heap, gc_ref);
    ctx_gc_pop_root_scope_internal(ctx);
    return result;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_parked_gc_root_probe(void) {
    return (int64_t)parked_gc_root_probe;
}

static int nested_trap_probe(
    jit_context_t *ctx,
    int64_t *values,
    void *func_ptr
) {
    (void)ctx;
    (void)values;
    g_trap_func_idx = (int)(intptr_t)func_ptr;
    g_trap_pc = (uintptr_t)nested_trap_probe;
    g_trap_code = 6;
    siglongjmp(g_trap_jmp_buf, 1);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_nested_trap_probe(void) {
    return (int64_t)nested_trap_probe;
}

static int64_t guard_access_probe(void *closure) {
    (void)closure;
    uintptr_t guard_base = 0;
    if (!wasmoon_native_fiber_stack_bounds(
            NULL, NULL, &guard_base, NULL
        )) {
        return 0;
    }
    volatile unsigned char *guard = (volatile unsigned char *)guard_base;
    *guard = 1;
    return 0;
}

MOONBIT_FFI_EXPORT int wasmoon_test_fiber_guard_rejects_access(void) {
    void *fiber = wasmoon_native_fiber_alloc(
        guard_access_probe,
        NULL,
        64 * 1024
    );
    if (!fiber) return 0;
    pid_t child = fork();
    if (child < 0) {
        moonbit_decref(fiber);
        return 0;
    }
    if (child == 0) {
        wasmoon_native_fiber_continue(fiber, 0);
        _exit(0);
    }
    int status = 0;
    int waited = waitpid(child, &status, 0);
    moonbit_decref(fiber);
    return waited == child && WIFSIGNALED(status);
}

MOONBIT_FFI_EXPORT int wasmoon_test_fiber_preserves_registers(void) {
    void *fiber = wasmoon_native_fiber_alloc(
        wasmoon_test_native_fiber_register_probe,
        NULL,
        64 * 1024
    );
    if (!fiber) return 0;
    int first = wasmoon_native_fiber_continue(fiber, 0);
    int second = first == WASMOON_FIBER_ADVANCE_SUSPENDED
        ? wasmoon_native_fiber_continue(fiber, 0)
        : WASMOON_FIBER_ADVANCE_INVALID_HANDLE;
    int passed = second == WASMOON_FIBER_ADVANCE_RETURNED &&
        wasmoon_native_fiber_return_value(fiber) == 1;
    moonbit_decref(fiber);
    return passed;
}
